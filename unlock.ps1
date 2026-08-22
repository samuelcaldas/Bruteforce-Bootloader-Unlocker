<#
.SYNOPSIS
    PowerShell bootloader-unlocker — parity port of the Bash bootloader_unlocker.

    Features:
      - Fastboot discovery: script folder -> CWD -> PATH
      - Device detection: 0 devices = hard stop, >1 = require -Device
      - IMEI-based per-device identity; falls back to sanitized serial
      - State (<identity>.dat) and log (<identity>.log) per device; resumes on restart
      - Command profile auto-detection matching Bash heuristics
      - Terminal error classification stops immediately (policy-denied, carrier lock, etc.)
      - Pattern DSL with weighted scheduling and deterministic resume by offset
      - Ctrl+C / unexpected exit saves progress via try/finally

.REQUIREMENTS
    PowerShell 5.1+, Android SDK Platform-Tools (fastboot.exe)

.PARAMETER Device
    Fastboot device serial. Required when multiple devices are connected.

.PARAMETER Command
    Unlock command profile:
    auto | flashing-unlock | flashing-unlock-code | oem-unlock-code | oem-unlock | oem-unlock-go
    Default: auto

.PARAMETER Strategy
    Code generation strategy: sequential | random | smart  (default: smart)
    smart = weighted round-robin across patterns by weight;
    sequential = first pattern only;
    random = random pattern selection each attempt.

.PARAMETER Pattern
    Single DSL mask (e.g. 'X{20}'). Overrides all other pattern settings.

.PARAMETER Patterns
    Semicolon-separated pattern list: name:mask:weight[;name:mask:weight...]

.PARAMETER Start
    Numeric offset to start from (overrides saved per-pattern offset for pattern index 0).

.PARAMETER HangTimeout
    Seconds to wait before treating a fastboot call as hung. Default: 30.
#>
param(
    [string]$Device      = "",
    [string]$Command     = "auto",
    [string]$Strategy    = "smart",
    [string]$Pattern     = "",
    [string]$Patterns    = "",
    [long]$Start         = -1,
    [int]$HangTimeout    = 30
)

# ─────────────────────────────────────────────────────────────────────────────
# 1  BUILT-IN PATTERN LIBRARY
# ─────────────────────────────────────────────────────────────────────────────
# Each entry: "name:mask:weight:note"  (higher weight = more attempts proportionally)
# Mirrors the BUILTIN_PATTERNS variable in the Bash script.
$BuiltinPatterns = @(
    "motorola-portal-20:X{20}:10:Motorola portal unlock keys (20 uppercase alphanumeric)"
    "motorola-last-digit:A{19}9:6:Motorola-like 20-char key, final digit"
    "motorola-pos5-digit:A{4}9A{15}:5:Motorola-like 20-char key, digit at position 5"
    "hex-16:H{16}:3:Common 16-char hex token"
    "hex-32:H{32}:2:Long 32-char hex token"
    "numeric-8:9{8}:2:Short 8-digit code"
    "numeric-6:9{6}:1:Short 6-digit code"
)

$StatusInterval = 10   # print progress line every N attempts
$SaveInterval   = 100  # persist state to disk every N attempts

# ─────────────────────────────────────────────────────────────────────────────
# 2  FASTBOOT DISCOVERY  (script folder -> CWD -> PATH)
# ─────────────────────────────────────────────────────────────────────────────
$script:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else {
    Split-Path -Parent $MyInvocation.MyCommand.Definition
}

function Get-FastbootPath {
    # (a) Beside this script — highest priority; avoids PATH ambiguity.
    # (b) Current working directory — user launched from platform-tools folder.
    # (c) PATH — standard system install.
    foreach ($candidate in @(
        (Join-Path $script:ScriptRoot      "fastboot.exe"),
        (Join-Path (Get-Location).Path     "fastboot.exe")
    )) {
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    foreach ($name in @("fastboot.exe", "fastboot")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    throw "fastboot.exe not found. Place it beside unlock.ps1, in the current folder, or add it to PATH."
}

$script:FastbootBin = Get-FastbootPath
Write-Host "[OK] fastboot: $($script:FastbootBin)"

# ─────────────────────────────────────────────────────────────────────────────
# 3  FASTBOOT WRAPPER  (hang detection via WaitForExit, in-memory async capture)
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-Fastboot {
    param(
        [string[]]$Arguments,
        [string]$Serial = ""
    )
    # Prepend -s <serial> when targeting a specific device.
    $allArgs = if ($Serial) { @("-s", $Serial) + $Arguments } else { $Arguments }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName              = $script:FastbootBin
    $psi.WorkingDirectory       = Split-Path -Parent $script:FastbootBin
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    foreach ($a in $allArgs) { $psi.ArgumentList.Add($a) }

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()

    # Drain both streams asynchronously (no temp files) — reading them
    # concurrently, rather than sequentially after exit, avoids the classic
    # redirect deadlock where the child blocks on a full pipe.
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    # WaitForExit blocks efficiently at the OS level and returns the instant
    # the process exits, instead of the old 200ms poll loop's built-in lag.
    if (-not $proc.WaitForExit($HangTimeout * 1000)) {
        Write-Host "  [WARN] fastboot '$($Arguments -join ' ')' hung (> $HangTimeout s). Killing."
        try { $proc.Kill() } catch {}
        return "HANG"
    }

    [System.Threading.Tasks.Task]::WaitAll(@($outTask, $errTask), 2000) | Out-Null
    return ($outTask.Result + $errTask.Result).TrimEnd()
}

# ─────────────────────────────────────────────────────────────────────────────
# 4  DEVICE DETECTION
# ─────────────────────────────────────────────────────────────────────────────
function Select-Device {
    param([string]$Requested)

    $raw     = Invoke-Fastboot -Arguments @("devices")
    # Extract serial numbers from lines matching "<serial>  fastboot"
    $serials = @(
        $raw -split '\r?\n' |
        Where-Object { $_ -match '\S' } |
        ForEach-Object { if ($_ -match '^([A-Za-z0-9:._-]+)\s+fastboot') { $Matches[1] } } |
        Where-Object { $_ }
    )

    if ($Requested) {
        # Validate the requested device is present.
        if ($serials -notcontains $Requested) {
            Write-Host "[ERR] Device '$Requested' not found in fastboot output."
            Write-Host "Connected devices:"
            Write-Host $raw
            exit 1
        }
        return $Requested
    }

    if ($serials.Count -eq 0) {
        Write-Host "[ERR] No fastboot device detected. Hard stop."
        Write-Host "  Put device in bootloader/fastboot mode, then re-run."
        Write-Host "  Common path: enable OEM unlocking, connect USB, run 'adb reboot bootloader'."
        exit 1
    }

    if ($serials.Count -gt 1) {
        Write-Host "[ERR] Multiple fastboot devices detected. Use -Device <id> to specify one."
        Write-Host $raw
        exit 1
    }

    return $serials[0]
}

# ─────────────────────────────────────────────────────────────────────────────
# 5  IDENTITY  (IMEI preferred; sanitized serial as fallback)
# ─────────────────────────────────────────────────────────────────────────────
function Get-DeviceIdentity {
    param([string]$Serial)
    # Attempt to read IMEI from fastboot vars — not all devices expose this.
    $out = Invoke-Fastboot -Arguments @("getvar", "all") -Serial $Serial
    foreach ($line in ($out -split '\r?\n')) {
        if ($line -match '(?i)\bimei\b\s*:\s*(\S+)') {
            $imei = $Matches[1] -replace '[^A-Za-z0-9_-]', '_'
            if ($imei.Length -gt 3) { return "IMEI_$imei" }
        }
    }
    # Fall back to sanitized serial (safe for use as filename component).
    return ($Serial -replace '[^A-Za-z0-9._-]', '_')
}

# ─────────────────────────────────────────────────────────────────────────────
# 6  STATE FILE  (key=value pairs, one per line)
# ─────────────────────────────────────────────────────────────────────────────
$script:StateFile   = $null
$script:SuccessFile = $null
$script:LogFile     = $null
$script:State       = @{}

function Initialize-FilePaths {
    param([string]$Identity)
    $script:StateFile   = Join-Path $script:ScriptRoot "${Identity}.dat"
    $script:SuccessFile = Join-Path $script:ScriptRoot "SUCCESS_${Identity}.txt"
    $script:LogFile     = Join-Path $script:ScriptRoot "${Identity}.log"
}

function Read-StateFile {
    if (-not (Test-Path $script:StateFile)) { return }
    foreach ($line in (Get-Content $script:StateFile -Encoding UTF8)) {
        if ($line -match '^([^=]+)=(.*)$') {
            $script:State[$Matches[1].Trim()] = $Matches[2]
        }
    }
}

function Save-StateFile {
    if (-not $script:StateFile) { return }
    $lines = @()
    foreach ($k in $script:State.Keys) { $lines += "${k}=$($script:State[$k])" }
    Set-Content -Path $script:StateFile -Value $lines -Encoding UTF8
}

# ─────────────────────────────────────────────────────────────────────────────
# 7  LOGGING
# ─────────────────────────────────────────────────────────────────────────────
function Write-Log {
    param([string]$Msg)
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Msg"
    if ($script:LogFile) {
        $entry | Tee-Object -FilePath $script:LogFile -Append | Out-Host
    } else {
        Write-Host $entry
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 8  COMMAND PROFILE DETECTION  (mirrors detect_unlock_command in Bash)
# ─────────────────────────────────────────────────────────────────────────────
function Resolve-CommandProfile {
    param([string]$Requested, [string]$Serial)

    $valid = @("auto","flashing-unlock","flashing-unlock-code","oem-unlock-code","oem-unlock","oem-unlock-go")
    if ($Requested -notin $valid) {
        Write-Log "[ERR] Invalid profile '$Requested'. Valid: $($valid -join ', ')"
        exit 1
    }
    if ($Requested -ne "auto") {
        Write-Log "[OK] Profile: $Requested (manual)"
        return $Requested
    }

    Write-Log "Autodetecting unlock profile..."

    # Heuristic 1: AOSP flashing unlock ability flag.
    $ability = Invoke-Fastboot -Arguments @("flashing", "get_unlock_ability") -Serial $Serial
    if ($ability -match '(?<![0-9])1(?![0-9])') {
        Write-Log "[OK] AOSP unlock ability = 1 -> flashing-unlock"
        return "flashing-unlock"
    }

    # Heuristic 2: OEM unlock-data response (Motorola / token-issuing devices).
    $unlockData = Invoke-Fastboot -Arguments @("oem", "get_unlock_data") -Serial $Serial

    # AOSP/Pixel bootloaders don't implement any 'oem' subcommand at all and
    # reject it outright -- that rejection is itself strong evidence this is
    # a flashing-unlock device, not weak evidence to fall through on.
    if ($unlockData -match '(?i)(unknown.?command|not.?supported|invalid.?oem.?command|no.?such.?command)') {
        Write-Log "[OK] Device rejects 'oem' subcommands (AOSP-style bootloader) -> flashing-unlock"
        return "flashing-unlock"
    }

    if (($unlockData -match '(?i)(unlock.?data|bootloader|INFO|Motorola|token)') -and
        ($unlockData -notmatch '(?i)(FAILED|remote failure)')) {
        Write-Log "[OK] OEM unlock-data responded with token data -> oem-unlock-code"
        return "oem-unlock-code"
    }

    # Heuristic 3: Product name (Pixel/Google devices use standard AOSP flashing unlock).
    $product = Invoke-Fastboot -Arguments @("getvar", "product") -Serial $Serial
    if ($product -match '(?i)(pixel|google)') {
        Write-Log "[OK] Pixel/Google product -> flashing-unlock"
        return "flashing-unlock"
    }

    # Conservative default: choose code-based flow rather than false-failing on ambiguous responses.
    Write-Log "[WARN] Cannot confirm no-code support; defaulting to conservative: oem-unlock-code"
    return "oem-unlock-code"
}

function Test-ProfileNeedsCode {
    param([string]$Profile)
    return $Profile -notin @("flashing-unlock", "oem-unlock", "oem-unlock-go")
}

# ─────────────────────────────────────────────────────────────────────────────
# 9  PATTERN DSL
# ─────────────────────────────────────────────────────────────────────────────
# Case-sensitive character set map (PowerShell hash literals are case-insensitive,
# so 'A' and 'a' would collide; use an Ordinal-keyed Dictionary instead).
$script:DslCharsets = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::Ordinal)
$script:DslCharsets.Add('9', '0123456789')
$script:DslCharsets.Add('A', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ')
$script:DslCharsets.Add('a', 'abcdefghijklmnopqrstuvwxyz')
$script:DslCharsets.Add('X', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789')
$script:DslCharsets.Add('x', 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789')
$script:DslCharsets.Add('H', '0123456789ABCDEF')
$script:DslCharsets.Add('h', '0123456789abcdef')
$script:DslCharsets.Add('?', 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789')

function Expand-DslMask {
    # Expand {n} repeat quantifiers, e.g. X{20} -> XXXXXXXXXXXXXXXXXXXX.
    param([string]$Mask)
    $sb = [System.Text.StringBuilder]::new()
    $i  = 0
    while ($i -lt $Mask.Length) {
        $ch    = $Mask[$i]
        $count = 1
        if (($i + 1) -lt $Mask.Length -and $Mask[$i + 1] -eq '{') {
            $j   = $i + 2
            $num = ""
            while ($j -lt $Mask.Length -and $Mask[$j] -ne '}') { $num += $Mask[$j]; $j++ }
            if ($j -lt $Mask.Length -and $num -match '^\d+$' -and [int]$num -gt 0) {
                $count = [int]$num
                $i     = $j   # advance past the closing '}'
            }
        }
        [void]$sb.Append([string]$ch * $count)
        $i++
    }
    return $sb.ToString()
}

function Get-CharsetForSymbol {
    param([string]$Symbol)
    if ($script:DslCharsets.ContainsKey($Symbol)) { return $script:DslCharsets[$Symbol] }
    return $Symbol   # literal character pass-through
}

function ConvertTo-PatternCode {
    # Mixed-radix (variable-base) conversion: offset -> deterministic code string.
    # Offset 0 = first candidate, 1 = second, etc. — enables reproducible resume.
    # Mirrors pattern_to_code() in the Bash script.
    param([long]$Offset, [string]$Mask)
    $expanded = Expand-DslMask $Mask
    $result   = [char[]]::new($expanded.Length)
    $off      = $Offset
    for ($i = $expanded.Length - 1; $i -ge 0; $i--) {
        $sym  = [string]$expanded[$i]
        $cs   = Get-CharsetForSymbol $sym
        $base = $cs.Length
        if ($base -le 1) {
            $result[$i] = if ($cs.Length -gt 0) { $cs[0] } else { $sym[0] }
        } else {
            $result[$i] = $cs[[int]($off % $base)]
            $off        = [long][Math]::Floor($off / $base)
        }
    }
    return [string]::new($result)
}

function Get-PatternSpace {
    # Total unique codes a mask can produce; returns "huge" on overflow.
    param([string]$Mask)
    $expanded = Expand-DslMask $Mask
    [long]$total = 1
    foreach ($sym in $expanded.ToCharArray()) {
        $cs   = Get-CharsetForSymbol ([string]$sym)
        $base = $cs.Length
        if ($base -gt 1) {
            if ($total -gt ([long]::MaxValue / $base)) { return "huge" }
            $total *= $base
        }
    }
    return $total
}

function Get-RandomCode {
    # Generate a single random code from a DSL mask (used by the 'random' strategy).
    param([string]$Mask, [System.Random]$Rng)
    $expanded = Expand-DslMask $Mask
    $result   = [char[]]::new($expanded.Length)
    for ($i = 0; $i -lt $expanded.Length; $i++) {
        $cs = Get-CharsetForSymbol ([string]$expanded[$i])
        $result[$i] = if ($cs.Length -gt 1) { $cs[$Rng.Next(0, $cs.Length)] } else { $cs[0] }
    }
    return [string]::new($result)
}

# ─────────────────────────────────────────────────────────────────────────────
# 10  PATTERN ENTRY PARSER
# ─────────────────────────────────────────────────────────────────────────────
function ConvertTo-PatternEntries {
    # Parse an array of "name:mask:weight:note" strings into PSCustomObjects.
    # The note field is optional and may itself contain colons.
    param([string[]]$Lines)
    $list = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($raw in $Lines) {
        $part = $raw.Trim()
        if (-not $part) { continue }
        $i1 = $part.IndexOf(':')
        if ($i1 -lt 0) {
            $list.Add([pscustomobject]@{ Name = "pattern"; Mask = $part; Weight = 1; Note = "" })
            continue
        }
        $name  = $part.Substring(0, $i1)
        $rest  = $part.Substring($i1 + 1)
        $i2    = $rest.IndexOf(':')
        if ($i2 -lt 0) {
            $list.Add([pscustomobject]@{ Name = $name; Mask = $rest; Weight = 1; Note = "" })
            continue
        }
        $mask  = $rest.Substring(0, $i2)
        $rest2 = $rest.Substring($i2 + 1)
        $i3    = $rest2.IndexOf(':')
        $wStr  = if ($i3 -ge 0) { $rest2.Substring(0, $i3) } else { $rest2 }
        $note  = if ($i3 -ge 0) { $rest2.Substring($i3 + 1) } else { "" }
        $w     = if ($wStr -match '^\d+$' -and [int]$wStr -gt 0) { [int]$wStr } else { 1 }
        $list.Add([pscustomobject]@{ Name = $name; Mask = $mask; Weight = $w; Note = $note })
    }
    return @($list)   # @() ensures array even for 0 or 1 items
}

# ─────────────────────────────────────────────────────────────────────────────
# 11  PATTERN SCHEDULING  (mirrors weighted_pattern_index / random_pattern_index)
# ─────────────────────────────────────────────────────────────────────────────
function Get-TotalWeight { param([object[]]$Entries)
    $t = 0; foreach ($e in $Entries) { $t += $e.Weight }; return $t
}

function Get-WeightedPatternIndex {
    # Deterministic weighted selection: cursor % totalWeight picks a proportional slot.
    param([object[]]$Entries, [long]$Cursor)
    $total = Get-TotalWeight $Entries
    if ($total -le 0) { return 0 }
    [long]$slot = $Cursor % $total
    [long]$cum  = 0
    for ($i = 0; $i -lt $Entries.Count; $i++) {
        $cum += $Entries[$i].Weight
        if ($slot -lt $cum) { return $i }
    }
    return 0
}

function Get-RandomPatternIndex {
    param([object[]]$Entries, [System.Random]$Rng)
    [long]$total = Get-TotalWeight $Entries
    if ($total -le 0) { return 0 }
    # Clamp to Int32 range for System.Random.Next; pattern weights are expected to be small.
    $maxVal = [Math]::Min($total, [int]::MaxValue)
    [long]$slot = $Rng.Next(0, [int]$maxVal)
    [long]$cum  = 0
    for ($i = 0; $i -lt $Entries.Count; $i++) {
        $cum += $Entries[$i].Weight
        if ($slot -lt $cum) { return $i }
    }
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# 12  ERROR CLASSIFICATION  (mirrors is_terminal_fastboot_error / is_fastboot_failure)
# ─────────────────────────────────────────────────────────────────────────────

# Patterns that indicate the device will never accept an unlock in its current state.
# Checked individually so each is easy to read and extend.
$TerminalErrorPatterns = @(
    '(?i)unknown.?command',              # fastboot command not understood by device
    '(?i)not.?supported',                # feature explicitly unsupported
    '(?i)not.?allowed',                  # OEM/policy block (covers "not allowed" variants)
    '(?i)unlock.?ability.?is.?0',        # get_unlock_ability returned 0
    '(?i)unlock_ability.*0',             # alternate format for unlock ability = 0
    '(?i)oem.?unlock.?is.?not.?allowed', # explicit oem unlock policy denial
    '(?i)flashing.?unlock.?is.?not.?allowed', # explicit flashing unlock policy denial
    '(?i)permission.?denied',            # OS-level permission block
    '(?i)locked.?by.?carrier',           # carrier/SIM lock
    '(?i)carrier.?lock',
    '(?i)\bfrp\b',                       # Factory Reset Protection active
    '(?i)not.?unlockable',               # device flagged as non-unlockable
    '(?i)bootloader.?lock'               # bootloader locked by policy (e.g. enterprise MDM)
)

# Patterns that indicate a generic (retryable) failure — wrong code, transient error, etc.
$FailurePatterns = @(
    '(?i)FAILED',
    '(?i)fail(ed|ure)?',
    '(?i)\berror\b',
    '(?i)\binvalid\b',
    '(?i)\bdenied\b',
    '(?i)\bwrong\b',
    '(?i)\bincorrect\b',
    '(?i)not.?match',
    '(?i)mismatch',
    '(?i)remote:'
)

function Test-TerminalError {
    # Returns $true when output signals a condition that will not change on retry.
    # Stop immediately — retrying is pointless and may worsen the situation.
    param([string]$Output)
    foreach ($pat in $TerminalErrorPatterns) {
        if ($Output -match $pat) { return $true }
    }
    return $false
}

function Test-FastbootFailure {
    # Returns $true when output contains a generic failure indicator.
    param([string]$Output)
    foreach ($pat in $FailurePatterns) {
        if ($Output -match $pat) { return $true }
    }
    return $false
}

# ─────────────────────────────────────────────────────────────────────────────
# 13  UNLOCK COMMAND DISPATCHER
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-UnlockCommand {
    param([string]$Profile, [string]$Serial, [string]$Code = "")
    switch ($Profile) {
        "flashing-unlock"      { return Invoke-Fastboot -Arguments @("flashing", "unlock")       -Serial $Serial }
        "flashing-unlock-code" { return Invoke-Fastboot -Arguments @("flashing", "unlock", $Code) -Serial $Serial }
        "oem-unlock"           { return Invoke-Fastboot -Arguments @("oem", "unlock")             -Serial $Serial }
        "oem-unlock-code"      { return Invoke-Fastboot -Arguments @("oem", "unlock", $Code)      -Serial $Serial }
        "oem-unlock-go"        { return Invoke-Fastboot -Arguments @("oem", "unlock-go")          -Serial $Serial }
        default { Write-Log "[ERR] Unknown profile: $Profile"; exit 1 }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 13.4  UNLOCK VERIFICATION  (reapply + confirm via 'getvar unlocked')
# ─────────────────────────────────────────────────────────────────────────────
function Get-UnlockedState {
    # Returns 'yes', 'no', or 'unknown' (device doesn't expose the var).
    param([string]$Serial)
    $out = Invoke-Fastboot -Arguments @("getvar", "unlocked") -Serial $Serial
    if ($out -match '(?i)unlocked:\s*yes') { return "yes" }
    if ($out -match '(?i)unlocked:\s*no')  { return "no" }
    return "unknown"
}

function Confirm-Unlock {
    # A non-failure fastboot response is a weak signal on its own. Reapply the
    # same unlock command once more, then check the device's own state var
    # rather than just trusting the absence of a failure string.
    param([string]$Profile, [string]$Serial, [string]$Code = "")

    Write-Log "Reapplying unlock command to confirm..."
    $reapply = Invoke-UnlockCommand -Profile $Profile -Serial $Serial -Code $Code
    Write-Log $reapply
    if (Test-TerminalError $reapply) {
        Write-Log "[WARN] Reapply hit a terminal error; not confirmed."
        return "no"
    }

    Start-Sleep -Milliseconds 1000
    $state = Get-UnlockedState -Serial $Serial
    switch ($state) {
        "yes"     { Write-Log "[OK] CONFIRMED: 'fastboot getvar unlocked' reports yes." }
        "no"      { Write-Log "[WARN] NOT confirmed: device still reports unlocked=no. It may need on-device confirmation (volume/power) before it takes effect." }
        "unknown" { Write-Log "[WARN] Device does not expose 'unlocked' getvar; cannot auto-verify. Check the device screen manually." }
    }
    return $state
}

# ─────────────────────────────────────────────────────────────────────────────
# 13.5  POST-UNLOCK HINT  (GrapheneOS install pointer; opt-in browser hand-off)
# ─────────────────────────────────────────────────────────────────────────────
function Write-GrapheneOSInstallHint {
    param([string]$Serial)
    $product = Invoke-Fastboot -Arguments @("getvar", "product") -Serial $Serial
    $codename = if ($product -match '(?i)product:\s*(\S+)') { $Matches[1] } else { "" }

    $releasesUrl = "https://grapheneos.org/releases"
    $installUrl  = "https://grapheneos.org/install/cli"

    Write-Log "------------------------------------------------------------"
    Write-Log "Bootloader unlocked. To install GrapheneOS:"
    if ($codename) { Write-Log "  Device codename (reported): $codename" }
    Write-Log "  1. Check device support and get the factory image: $releasesUrl"
    Write-Log "  2. Follow the official CLI install instructions:  $installUrl"
    Write-Log "  (This script does not download, verify, or flash a factory image itself --"
    Write-Log "   the official install page handles checksum/signature verification, which"
    Write-Log "   matters a lot for a security-focused OS like this.)"

    $resp = Read-Host "Open the official GrapheneOS install page in your browser now? [y/N]"
    if ($resp -match '^[Yy]') {
        try {
            Start-Process $installUrl
            Write-Log "[OK] Opened $installUrl in default browser."
        } catch {
            Write-Log "[WARN] Could not open browser automatically: $($_.Exception.Message)"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 14  MAIN
# ─────────────────────────────────────────────────────────────────────────────

# --- Device detection ---
Write-Host ""
Write-Host "FASTBOOT UNLOCK CONSOLE"
Write-Host "------------------------------------------------------------"
Write-Host "Detecting fastboot device..."
$selectedSerial = Select-Device -Requested $Device
Write-Host "[OK] Device: $selectedSerial"

# --- Identity (IMEI preferred, serial fallback) ---
Write-Host "Determining device identity..."
$identity = Get-DeviceIdentity -Serial $selectedSerial
Write-Host "[OK] Identity: $identity"

# --- Initialize per-identity paths and load saved state ---
Initialize-FilePaths -Identity $identity
Read-StateFile

Write-Host "[OK] State file: $($script:StateFile)"
Write-Host "[OK] Log file:   $($script:LogFile)"
Write-Host ""

Write-Log "======== Session start ========"
Write-Log "Device:   $selectedSerial"
Write-Log "Identity: $identity"

# --- Resolve command profile: CLI > saved state > auto-detect ---
$resolvedProfile = if ($Command -ne "auto") {
    $Command
} elseif ($script:State["resolved_command"]) {
    $p = $script:State["resolved_command"]
    Write-Log "Resuming with saved profile: $p"
    $p
} else {
    Resolve-CommandProfile -Requested $Command -Serial $selectedSerial
}
$script:State["resolved_command"] = $resolvedProfile
Write-Log "Profile:  $resolvedProfile"

# --- Already succeeded? Verify against the live device before trusting it. ---
if (Test-Path $script:SuccessFile) {
    $prev = (Get-Content $script:SuccessFile -Raw).Trim()
    Write-Log "Success file exists (code: $prev). Verifying against live device state..."
    $state = Get-UnlockedState -Serial $selectedSerial
    if ($state -eq "yes") {
        Write-Log "[OK] CONFIRMED: device reports unlocked. Code: $prev"
        Write-Log "     Delete $($script:SuccessFile) to re-run."
        Write-GrapheneOSInstallHint -Serial $selectedSerial
        exit 0
    } elseif ($state -eq "no") {
        Write-Log "[WARN] Success file exists but the device reports unlocked=no -- stale or incorrect record."
        Write-Log "       Ignoring $($script:SuccessFile) and continuing."
    } else {
        Write-Log "[WARN] Device does not expose 'unlocked' getvar; cannot verify the saved success file."
        Write-Log "       Trusting it (delete $($script:SuccessFile) to force a re-run)."
        Write-GrapheneOSInstallHint -Serial $selectedSerial
        exit 0
    }
}

# ── NO-CODE PROFILE: run once and classify result ─────────────────────────────
if (-not (Test-ProfileNeedsCode $resolvedProfile)) {
    Write-Log "Profile does not require a code; running command once."
    Write-Log "(Pattern attempts are not applicable for this profile.)"

    $out = Invoke-UnlockCommand -Profile $resolvedProfile -Serial $selectedSerial
    Write-Log $out

    if (Test-TerminalError $out) {
        Write-Log "[ERR] Terminal error: OEM unlock disabled, carrier lock, or device policy block."
        Write-Log "      Stopping immediately. Enable OEM unlock in developer options and retry."
        Save-StateFile
        exit 1
    }

    if (-not (Test-FastbootFailure $out)) {
        $state = Confirm-Unlock -Profile $resolvedProfile -Serial $selectedSerial
        if ($state -eq "no") {
            Write-Log "[ERR] Command sent but device is not confirmed unlocked yet."
            Write-Log "      If prompted, confirm on the device screen (volume/power), then re-run this script to verify."
            Save-StateFile
            exit 1
        }
        Write-Log "[OK] Command sent. Confirm unlock on device screen if prompted."
        Set-Content -Path $script:SuccessFile -Value "(no-code unlock sent)" -Encoding UTF8
        Save-StateFile
        Write-GrapheneOSInstallHint -Serial $selectedSerial
        exit 0
    }

    Write-Log "[ERR] Unlock command failed."
    Save-StateFile
    exit 1
}

# ── CODE-BASED PROFILE: build pattern schedule ────────────────────────────────
$patternLines = if ($Patterns) {
    @($Patterns -split ';')
} elseif ($Pattern) {
    @("custom:${Pattern}:10:User-provided mask")
} elseif ($script:State["patterns_str"]) {
    @($script:State["patterns_str"] -split ';')
} else {
    $BuiltinPatterns
}

$patternEntries = @(ConvertTo-PatternEntries -Lines $patternLines)

if ($patternEntries.Count -eq 0) {
    Write-Log "[ERR] No valid pattern entries. Check -Pattern or -Patterns arguments."
    exit 1
}

# Persist pattern list so resumed runs use the same set.
$script:State["patterns_str"] = ($patternLines | Where-Object { $_ }) -join ";"

# Load per-pattern offsets from saved state (comma-separated longs).
[long[]]$offsets = [long[]]::new($patternEntries.Count)   # default all zeros
if ($script:State["pattern_offsets"]) {
    $saved = @($script:State["pattern_offsets"] -split ',')
    for ($i = 0; $i -lt $patternEntries.Count; $i++) {
        if ($i -lt $saved.Count -and $saved[$i] -match '^\d+$') {
            $offsets[$i] = [long]$saved[$i]
        }
    }
}

# -Start overrides the offset only for pattern index 0 (the highest-priority pattern).
# Pattern index 0 is the first entry in the active pattern list (shown in the plan above).
# To resume a specific run, use the offset printed in the log or status line.
if ($Start -ge 0) {
    $offsets[0] = $Start
    Write-Log "Starting from offset $Start (pattern 0)"
}

$resolvedStrategy = if ($Strategy -ne "smart") { $Strategy }
                    elseif ($script:State["strategy"]) { $script:State["strategy"] }
                    else { "smart" }
$script:State["strategy"] = $resolvedStrategy

# Print runtime plan.
Write-Log "Strategy: $resolvedStrategy"
Write-Log "Patterns:"
foreach ($e in $patternEntries) {
    $sp = Get-PatternSpace $e.Mask
    Write-Log "  - $($e.Name)  mask=$($e.Mask)  weight=$($e.Weight)  space=$sp"
}
Write-Log "Press Ctrl+C to save progress and exit."
Write-Log "------------------------------------------------------------"

# ── CODE ATTEMPT LOOP ─────────────────────────────────────────────────────────
$rng       = [System.Random]::new()
[long]$cursor = if ($script:State["last_value"] -match '^\d+$') { [long]$script:State["last_value"] } else { 0L }
$startTime = [DateTime]::Now

try {
    while ($true) {
        # Select pattern index based on strategy.
        $idx = switch ($resolvedStrategy) {
            "random"     { Get-RandomPatternIndex  -Entries $patternEntries -Rng $rng }
            "sequential" { 0 }
            default      { Get-WeightedPatternIndex -Entries $patternEntries -Cursor $cursor }
        }

        $entry  = $patternEntries[$idx]
        $offset = $offsets[$idx]

        # Wrap offset when the full pattern space has been exhausted.
        $space = Get-PatternSpace $entry.Mask
        if ($space -ne "huge" -and [long]$space -gt 0 -and $offset -ge [long]$space) {
            $offsets[$idx] = 0
            $offset = 0
        }

        # Generate candidate code (deterministic by offset, or random for 'random' strategy).
        $code = if ($resolvedStrategy -eq "random") {
            Get-RandomCode -Mask $entry.Mask -Rng $rng
        } else {
            ConvertTo-PatternCode -Offset $offset -Mask $entry.Mask
        }

        # Send the unlock command.
        $out = Invoke-UnlockCommand -Profile $resolvedProfile -Serial $selectedSerial -Code $code

        # Terminal error: policy-denied, carrier lock, etc. — stop immediately.
        if (Test-TerminalError $out) {
            Write-Host ""
            Write-Log "[ERR] TERMINAL FASTBOOT ERROR:"
            Write-Log "      $out"
            Write-Log "      Stopping: OEM unlock disabled, carrier lock, or device policy block."
            break
        }

        # Success: no failure indicators in the output.
        if (-not (Test-FastbootFailure $out)) {
            Write-Host ""
            $state = Confirm-Unlock -Profile $resolvedProfile -Serial $selectedSerial -Code $code
            if ($state -eq "no") {
                Write-Log "[WARN] Code '$code' looked promising but was not confirmed unlocked. Treating as a false positive and continuing."
                $offsets[$idx]++
                $cursor++
                continue
            }
            Write-Log "[OK] SUCCESS -- unlock code: $code"
            Set-Content -Path $script:SuccessFile -Value $code -Encoding UTF8
            Write-Log "[OK] Saved to $($script:SuccessFile)"
            Write-GrapheneOSInstallHint -Serial $selectedSerial
            break
        }

        # Advance counters.
        $offsets[$idx]++
        $cursor++

        # Periodic status line (overwritten in-place on the same console row).
        if ($cursor % $StatusInterval -eq 0) {
            $elapsed  = [int]([DateTime]::Now - $startTime).TotalSeconds
            $progress = if ($space -ne "huge" -and [long]$space -gt 0) {
                "{0:F3}%" -f ($offsets[$idx] * 100.0 / [long]$space)
            } else { "n/a" }
            # Build status parts separately for readability before joining.
            $statusParts = @(
                "Trying: $code",
                "Attempt: $cursor",
                "Pattern: $($entry.Name) ($($entry.Mask))",
                "Offset: $($offsets[$idx])",
                "Progress: $progress",
                "Elapsed: ${elapsed}s"
            )
            Write-Host ("`r$($statusParts -join ' | ')   ") -NoNewline
        }

        # Periodic log entry + state persistence.
        if ($cursor % $SaveInterval -eq 0) {
            # Log to file (not to console to avoid disrupting the status line).
            $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            "$stamp Attempt $cursor | Pattern: $($entry.Name) | Offset: $($offsets[$idx]) | Last: $code" |
                Add-Content -Path $script:LogFile -Encoding UTF8
            $script:State["last_value"]      = $cursor
            $script:State["pattern_offsets"] = $offsets -join ","
            Save-StateFile
        }
    }
} finally {
    # Runs on Ctrl+C, unexpected errors, and normal loop exit — always persist progress.
    $script:State["last_value"]      = $cursor
    $script:State["pattern_offsets"] = $offsets -join ","
    Save-StateFile
    Write-Host ""
    Write-Host "Progress saved to $($script:StateFile)"
    Write-Host "Resume with: .\unlock.ps1"
}

<#
.SYNOPSIS
    Bootloader Unlocker Script - Optimized for Motorola Devices
.DESCRIPTION
    This script attempts to unlock Android device bootloaders by brute-forcing unlock codes.
    It's specifically optimized for Motorola devices with patterns like "YOMSDTQYCNSVKO5HHODQ".
.PARAMETER Device
    The device ID to unlock. If not specified, automatically detects connected fastboot device.
.PARAMETER CodeType
    The type of code to generate: numeric, alpha, or moto (default: moto).
.PARAMETER CodeLength
    The length of the unlock code (default: 20 for Motorola devices).
.PARAMETER StartCode
    Start brute-forcing from a specific code.
.PARAMETER Pattern
    Use a specific Motorola pattern (1 or 2).
    1 = 19 uppercase letters + 1 number at the end
    2 = 4 uppercase letters + 1 number + 15 uppercase letters
.PARAMETER Strategy
    Brute-force strategy: sequential, random, or smart (default: sequential).
.EXAMPLE
    .\bootloader_unlocker.ps1 -CodeType moto -Pattern 1
.NOTES
    Author: Samuel Caldas
    Version: 2.0
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$Device,
    
    [Parameter()]
    [ValidateSet("numeric", "alpha", "moto")]
    [string]$CodeType,
    
    [Parameter()]
    [int]$CodeLength,
    
    [Parameter()]
    [string]$StartCode,
    
    [Parameter()]
    [ValidateSet("1", "2")]
    [string]$Pattern,
    
    [Parameter()]
    [ValidateSet("sequential", "random", "smart")]
    [string]$Strategy
)

# Clear the screen
Clear-Host

#region CONFIGURATION
# Default values for Motorola devices
$DEFAULT_CODE_LENGTH = 20
$DEFAULT_CHARACTER_SET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
$DEFAULT_STRATEGY = "sequential"
# Character sets
$numeric_charset = '0123456789'
$alpha_charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
$moto_charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'  # Optimized for Motorola
# PowerShell doesn't have a native way to define regex constants like Bash
# but we'll use these patterns in our code
# MOTO_PATTERN_1 = 19 uppercase letters followed by 1 number
# MOTO_PATTERN_2 = 4 uppercase letters, 1 number, 15 uppercase letters
#endregion

#region FUNCTIONS
function Show-Help {
    <#
    .SYNOPSIS
        Displays help information for the script.
    #>
    Write-Host "Bootloader Unlocker - Optimized for Motorola Devices" -ForegroundColor Cyan
    Write-Host "Usage: .\$($MyInvocation.MyCommand.Name) [options]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  -Device <id>     Specify device ID (default: auto-detect)"
    Write-Host "  -CodeType <type> Code type: numeric, alpha, moto (default: moto)"
    Write-Host "  -CodeLength <num> Code length (default: 20 for Motorola)"
    Write-Host "  -StartCode <code> Start from specific code"
    Write-Host "  -Pattern <num>   Use specific Motorola pattern (1 or 2)"
    Write-Host "  -Strategy <strategy> Bruteforce strategy: sequential, random, smart (default: sequential)"
    Write-Host ""
    Write-Host "Motorola-specific features:" -ForegroundColor Green
    Write-Host "  - Default 20-character codes"
    Write-Host "  - Optimized character set (mostly uppercase letters and numbers)"
    Write-Host "  - Pattern-specific brute forcing based on observed Motorola codes"
    Write-Host ""
    Write-Host "Example: .\$($MyInvocation.MyCommand.Name) -CodeType moto -Pattern 1" -ForegroundColor Yellow
    exit
}

function Read-DeviceData {
    <#
    .SYNOPSIS
        Reads device data from the file.
    .PARAMETER DeviceFile
        Path to the device data file.
    .OUTPUTS
        PSObject with device configuration.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$DeviceFile
    )
    
    $deviceData = [PSCustomObject]@{
        CodeType = "moto"
        CodeLength = $DEFAULT_CODE_LENGTH
        LastValue = 0
        Charset = $moto_charset
        Strategy = $DEFAULT_STRATEGY
        KnownPositions = ""
        MotoPattern = ""
    }
    
    if (Test-Path -Path $DeviceFile) {
        $content = Get-Content -Path $DeviceFile
        foreach ($line in $content) {
            if ($line -match '^(.+?)=(.*)$') {
                $key = $matches[1]
                $value = $matches[2]
                
                switch ($key) {
                    "code_type" { $deviceData.CodeType = $value }
                    "code_length" { $deviceData.CodeLength = [int]$value }
                    "last_value" { $deviceData.LastValue = [decimal]$value }
                    "charset" { $deviceData.Charset = $value }
                    "strategy" { $deviceData.Strategy = $value }
                    "known_positions" { $deviceData.KnownPositions = $value }
                    "moto_pattern" { $deviceData.MotoPattern = $value }
                }
            }
        }
    }
    
    return $deviceData
}

function Write-DeviceData {
    <#
    .SYNOPSIS
        Writes device data to the file.
    .PARAMETER DeviceFile
        Path to the device data file.
    .PARAMETER DeviceData
        Device configuration object.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$DeviceFile,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DeviceData
    )
    
    $content = @(
        "code_type=$($DeviceData.CodeType)",
        "code_length=$($DeviceData.CodeLength)",
        "last_value=$($DeviceData.LastValue)",
        "charset=$($DeviceData.Charset)",
        "strategy=$($DeviceData.Strategy)",
        "known_positions=$($DeviceData.KnownPositions)",
        "moto_pattern=$($DeviceData.MotoPattern)"
    )
    
    $content | Set-Content -Path $DeviceFile
}

function Convert-NumberToCode {
    <#
    .SYNOPSIS
        Converts a number to a code string based on the character set.
    .PARAMETER Number
        The number to convert.
    .PARAMETER Length
        The desired length of the code.
    .PARAMETER Charset
        The character set to use for conversion.
    .PARAMETER MotoPattern
        The Motorola pattern to apply (optional).
    .PARAMETER KnownPositions
        Known character positions in format "pos:char;pos:char" (optional).
    .OUTPUTS
        The generated code string.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [decimal]$Number,
        
        [Parameter(Mandatory = $true)]
        [int]$Length,
        
        [Parameter(Mandatory = $true)]
        [string]$Charset,
        
        [Parameter()]
        [string]$MotoPattern = "",
        
        [Parameter()]
        [string]$CodeType = "moto",
        
        [Parameter()]
        [string]$KnownPositions = ""
    )
    
    $base = $Charset.Length
    $code = ""
    $tempNum = $Number
    
    # Generate base code
    for ($i = 0; $i -lt $Length; $i++) {
        $index = $tempNum % $base
        $code = $Charset[$index] + $code
        $tempNum = [Math]::Floor($tempNum / $base)
    }
    
    # Apply pattern modifications if using a Motorola pattern
    if ($CodeType -eq "moto" -and $MotoPattern) {
        $modifiedCode = $code
        switch ($MotoPattern) {
            "1" {
                # Pattern 1: Ensure last character is a digit, rest are uppercase
                if ($modifiedCode[$Length-1] -notmatch '[0-9]') {
                    # Replace last character with a random digit
                    $digit = $numeric_charset[(Get-Random -Minimum 0 -Maximum 10)]
                    $modifiedCode = $modifiedCode.Substring(0, $Length-1) + $digit
                }
            }
            "2" {
                # Pattern 2: 4 uppercase letters, 1 number, 15 uppercase letters
                if ($modifiedCode[4] -notmatch '[0-9]') {
                    # Replace 5th character with a random digit
                    $digit = $numeric_charset[(Get-Random -Minimum 0 -Maximum 10)]
                    $modifiedCode = $modifiedCode.Substring(0, 4) + $digit + $modifiedCode.Substring(5)
                    $modifiedCode = $modifiedCode.Substring(0, $Length)
                }
            }
        }
        $code = $modifiedCode
    }
    
    # Apply any known positions
    if ($KnownPositions) {
        $positions = $KnownPositions -split ";"
        $tempCode = $code
        
        foreach ($position in $positions) {
            if ($position -match '^(\d+):([^;]+)$') {
                $pos = [int]$matches[1]
                $char = $matches[2]
                
                if ($pos -lt $tempCode.Length) {
                    $tempCode = $tempCode.Substring(0, $pos) + $char + $tempCode.Substring($pos + 1)
                }
            }
        }
        
        $code = $tempCode
    }
    
    return $code
}

function New-RandomCode {
    <#
    .SYNOPSIS
        Generates a random code.
    .PARAMETER Length
        The desired length of the code.
    .PARAMETER Charset
        The character set to use.
    .OUTPUTS
        A random code string.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [int]$Length,
        
        [Parameter(Mandatory = $true)]
        [string]$Charset
    )
    
    $code = ""
    $base = $Charset.Length
    
    for ($i = 0; $i -lt $Length; $i++) {
        $index = Get-Random -Minimum 0 -Maximum $base
        $code += $Charset[$index]
    }
    
    return $code
}

function Get-NextCode {
    <#
    .SYNOPSIS
        Generates the next code based on strategy.
    .PARAMETER DeviceData
        Device configuration object.
    .OUTPUTS
        The next code to try.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DeviceData
    )
    
    switch ($DeviceData.Strategy) {
        "random" {
            return New-RandomCode -Length $DeviceData.CodeLength -Charset $DeviceData.Charset
        }
        "smart" {
            # Example of a smarter algorithm for Motorola codes
            # For demonstration, we'll alternate between sequential and pattern-based
            if ($DeviceData.LastValue % 2 -eq 0) {
                return Convert-NumberToCode -Number $DeviceData.LastValue -Length $DeviceData.CodeLength -Charset $DeviceData.Charset
            }
            else {
                # Generate a code following Motorola patterns
                $baseCode = Convert-NumberToCode -Number $DeviceData.LastValue -Length $DeviceData.CodeLength -Charset $DeviceData.Charset
                
                if ($DeviceData.MotoPattern -eq "1") {
                    # Ensure last character is a digit
                    $digit = $numeric_charset[(Get-Random -Minimum 0 -Maximum 10)]
                    return $baseCode.Substring(0, 19) + $digit
                }
                elseif ($DeviceData.MotoPattern -eq "2") {
                    # 4 uppercase letters, 1 number, 15 uppercase letters
                    $digit = $numeric_charset[(Get-Random -Minimum 0 -Maximum 10)]
                    return $baseCode.Substring(0, 4) + $digit + $baseCode.Substring(5, 15)
                }
                else {
                    return $baseCode
                }
            }
        }
        default {
            # Sequential
            return Convert-NumberToCode -Number $DeviceData.LastValue -Length $DeviceData.CodeLength -Charset $DeviceData.Charset -MotoPattern $DeviceData.MotoPattern -CodeType $DeviceData.CodeType -KnownPositions $DeviceData.KnownPositions
        }
    }
}

function Get-TimeEstimate {
    <#
    .SYNOPSIS
        Estimates remaining time.
    .PARAMETER Current
        Current progress value.
    .PARAMETER Total
        Total work to be done.
    .PARAMETER Elapsed
        Time elapsed so far in seconds.
    .OUTPUTS
        Estimated time remaining as formatted string.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [decimal]$Current,
        
        [Parameter(Mandatory = $true)]
        [decimal]$Total,
        
        [Parameter(Mandatory = $true)]
        [int]$Elapsed
    )
    
    if ($Current -le 0) {
        return "Unknown"
    }
    
    $rate = $Current / $Elapsed
    if ($rate -le 0) {
        return "Unknown"
    }
    
    $remaining = [Math]::Floor(($Total - $Current) / $rate)
    
    # Format the time
    $days = [Math]::Floor($remaining / 86400)
    $hours = [Math]::Floor(($remaining % 86400) / 3600)
    $minutes = [Math]::Floor(($remaining % 3600) / 60)
    $seconds = $remaining % 60
    
    if ($days -gt 0) {
        return "${days}d ${hours}h ${minutes}m ${seconds}s"
    }
    elseif ($hours -gt 0) {
        return "${hours}h ${minutes}m ${seconds}s"
    }
    elseif ($minutes -gt 0) {
        return "${minutes}m ${seconds}s"
    }
    else {
        return "${seconds}s"
    }
}

function Test-UnlockWithCode {
    <#
    .SYNOPSIS
        Attempts to unlock the device with the given code.
    .PARAMETER Code
        The unlock code to try.
    .PARAMETER DeviceId
        The ID of the device to unlock.
    .OUTPUTS
        True if unlock was successful, false otherwise.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Code,
        
        [Parameter(Mandatory = $true)]
        [string]$DeviceId
    )
    
    try {
        $output = & fastboot oem unlock "$Code" 2>&1
        
        # Check if the unlock was successful
        if ($output -notmatch 'fail(ed|ure)?') {
            return $true  # Success
        }
        else {
            return $false  # Failure
        }
    }
    catch {
        Write-Warning "Error executing fastboot command: $_"
        return $false
    }
}

function Show-ProgressBar {
    <#
    .SYNOPSIS
        Displays a text-based progress bar.
    .PARAMETER Current
        Current progress value.
    .PARAMETER Total
        Total work to be done.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [decimal]$Current,
        
        [Parameter(Mandatory = $true)]
        [decimal]$Total
    )
    
    $length = 50
    $filled = [Math]::Floor($Current * $length / $Total)
    
    $progressBar = "["
    for ($i = 0; $i -lt $length; $i++) {
        if ($i -lt $filled) {
            $progressBar += "#"
        }
        else {
            $progressBar += " "
        }
    }
    $progressBar += "]"
    
    $percentage = [Math]::Round(($Current * 100) / $Total, 2)
    return "$progressBar $Current/$Total ($percentage%)"
}

function Get-DetectedDevice {
    <#
    .SYNOPSIS
        Detects connected fastboot devices.
    .OUTPUTS
        Device ID string or null if no device found.
    #>
    try {
        $devices = & fastboot devices 2>&1
        if ($devices) {
            # Extract first device ID
            $match = $devices -match '(\S+)\s+fastboot'
            if ($match) {
                return $matches[1]
            }
            
            # Alternative parsing if the above regex doesn't match
            $parts = $devices[0] -split '\s+'
            if ($parts.Count -gt 0) {
                return $parts[0]
            }
        }
    }
    catch {
        Write-Warning "Error detecting fastboot devices: $_"
    }
    
    return $null
}
#endregion

#region MAIN SCRIPT
# Display help if requested
if ($PSBoundParameters['Help']) {
    Show-Help
}

# Get the current device name
if ($Device) {
    $deviceId = $Device
}
else {
    $deviceId = Get-DetectedDevice
    if (-not $deviceId) {
        Write-Host "No device detected in fastboot mode. Please connect a device." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Current device: $deviceId" -ForegroundColor Cyan
$devFile = "./${deviceId}.dat"

# Check if we need to create a new device config or load existing
$createNewConfig = -not (Test-Path -Path $devFile) -or $PSBoundParameters.ContainsKey('CodeType') -or $PSBoundParameters.ContainsKey('CodeLength') -or $PSBoundParameters.ContainsKey('Strategy')

if ($createNewConfig) {
    # Initialize default device data
    $deviceData = [PSCustomObject]@{
        CodeType = "moto"
        CodeLength = $DEFAULT_CODE_LENGTH
        LastValue = 0
        Charset = $moto_charset
        Strategy = $DEFAULT_STRATEGY
        KnownPositions = ""
        MotoPattern = "1"  # Default to pattern 1 for Motorola
    }
    
    # Override with command line parameters if provided
    if ($PSBoundParameters.ContainsKey('CodeType')) {
        $deviceData.CodeType = $CodeType
    }
    elseif (-not (Test-Path -Path $devFile)) {
        # Prompt for code type if not specified
        Write-Host "Select code type:" -ForegroundColor Yellow
        Write-Host "1) Numeric (0-9)"
        Write-Host "2) Alphanumeric (A-Z, 0-9)"
        Write-Host "3) Motorola specific (optimized for Motorola devices)"
        $choice = Read-Host "Enter choice [3]"
        
        switch ($choice) {
            "1" { $deviceData.CodeType = "numeric" }
            "2" { $deviceData.CodeType = "alpha" }
            default { $deviceData.CodeType = "moto" }
        }
    }
    
    # Set code length
    if ($PSBoundParameters.ContainsKey('CodeLength')) {
        $deviceData.CodeLength = $CodeLength
    }
    elseif (-not (Test-Path -Path $devFile)) {
        if ($deviceData.CodeType -eq "moto") {
            $inputLength = Read-Host "Enter code length [$DEFAULT_CODE_LENGTH]"
            $deviceData.CodeLength = if ($inputLength) { [int]$inputLength } else { $DEFAULT_CODE_LENGTH }
        }
        else {
            $deviceData.CodeLength = [int](Read-Host "Enter code length")
        }
    }
    
    # Set strategy
    if ($PSBoundParameters.ContainsKey('Strategy')) {
        $deviceData.Strategy = $Strategy
    }
    elseif (-not (Test-Path -Path $devFile)) {
        Write-Host "Select brute force strategy:" -ForegroundColor Yellow
        Write-Host "1) Sequential (try all codes in order)"
        Write-Host "2) Random (try random codes)"
        Write-Host "3) Smart (use patterns and optimizations)"
        $choice = Read-Host "Enter choice [1]"
        
        switch ($choice) {
            "2" { $deviceData.Strategy = "random" }
            "3" { $deviceData.Strategy = "smart" }
            default { $deviceData.Strategy = "sequential" }
        }
    }
    
    # Set Motorola pattern if applicable
    if ($deviceData.CodeType -eq "moto") {
        if ($PSBoundParameters.ContainsKey('Pattern')) {
            $deviceData.MotoPattern = $Pattern
        }
        elseif (-not (Test-Path -Path $devFile)) {
            Write-Host "Select Motorola code pattern:" -ForegroundColor Yellow
            Write-Host "1) 19 uppercase letters + 1 number at the end (e.g., ABCDEFGHIJKLMNOPQRS5)"
            Write-Host "2) 4 uppercase letters + 1 number + 15 uppercase letters (e.g., ABCD5EFGHIJKLMNOPQRST)"
            Write-Host "3) No specific pattern"
            $choice = Read-Host "Enter choice [1]"
            
            switch ($choice) {
                "2" { $deviceData.MotoPattern = "2" }
                "3" { $deviceData.MotoPattern = "" }
                default { $deviceData.MotoPattern = "1" }
            }
        }
    }
    
    # Set starting value/code
    if ($PSBoundParameters.ContainsKey('StartCode')) {
        # TODO: Convert start code to number - this would require a complex algorithm
        # For now we'll just start from 0
        $deviceData.LastValue = 0
    }
    else {
        $deviceData.LastValue = 0
    }
    
    # Ask if user knows any specific positions in the code
    if (-not (Test-Path -Path $devFile)) {
        $hasKnown = Read-Host "Do you know any specific characters in the code? (y/n) [n]"
        if ($hasKnown -eq "y") {
            Write-Host "Enter known positions in format position:character (e.g., 5:A;10:B)" -ForegroundColor Yellow
            $deviceData.KnownPositions = Read-Host "> "
        }
    }
    
    # Set character set based on code type
    switch ($deviceData.CodeType) {
        "numeric" { $deviceData.Charset = $numeric_charset }
        "alpha" { $deviceData.Charset = $alpha_charset }
        "moto" { $deviceData.Charset = $moto_charset }
        default {
            Write-Host "Invalid code type: $($deviceData.CodeType)" -ForegroundColor Red
            exit 1
        }
    }
    
    # Write to device file
    Write-DeviceData -DeviceFile $devFile -DeviceData $deviceData
}
else {
    # Read from device file
    $deviceData = Read-DeviceData -DeviceFile $devFile
}

# Calculate total possible combinations
$base = $deviceData.Charset.Length
if ($deviceData.Strategy -eq "sequential") {
    # Using [Math]::Pow for large numbers
    $totalCombinations = [Math]::Pow($base, $deviceData.CodeLength)
    # Cap at a reasonable number for display purposes
    if ($totalCombinations -gt [double]::MaxValue) {
        $totalCombinations = [double]::MaxValue
    }
}
else {
    # For random and smart strategies, just use a large number for progress display
    $totalCombinations = 1000000
}

#region MAIN LOOP
# Register an event handler for Ctrl+C to save progress before exit
$null = Register-ObjectEvent -InputObject ([Console]) -EventName CancelKeyPress -Action {
    Write-Host "`nProgress saved. Resume with: .\bootloader_unlocker.ps1" -ForegroundColor Yellow
    Write-DeviceData -DeviceFile $devFile -DeviceData $deviceData
    [Environment]::Exit(0)
}

# Start time for estimation
$startTime = Get-Date
$attempts = 0
$statusUpdateInterval = 10  # Update status every 10 attempts

Write-Host "Starting bootloader unlock attempts..." -ForegroundColor Green
Write-Host "Code type: $($deviceData.CodeType), Length: $($deviceData.CodeLength), Strategy: $($deviceData.Strategy)"
if ($deviceData.CodeType -eq "moto" -and $deviceData.MotoPattern) {
    Write-Host "Using Motorola pattern: $($deviceData.MotoPattern)"
}
Write-Host "Press Ctrl+C to pause and save progress"
Write-Host "-" * 60

try {
    while ($true) {
        $code = Get-NextCode -DeviceData $deviceData
        
        # Try to unlock the device
        $success = Test-UnlockWithCode -Code $code -DeviceId $deviceId
        
        if ($success) {
            Write-Host "`nSUCCESS! Your unlock code is: $code" -ForegroundColor Green
            # Save the successful code
            $code | Out-File -FilePath "./SUCCESS_${deviceId}.txt"
            break
        }
        
        # Update progress
        $attempts++
        $deviceData.LastValue++
        
        # Only update the display occasionally to improve performance
        if ($attempts % $statusUpdateInterval -eq 0) {
            $currentTime = Get-Date
            $elapsed = ($currentTime - $startTime).TotalSeconds
            
            # Clear the line and show progress
            Write-Host -NoNewLine "`r" + (" " * 80) + "`r"
            
            if ($deviceData.Strategy -eq "sequential") {
                $remaining = Get-TimeEstimate -Current $deviceData.LastValue -Total $totalCombinations -Elapsed $elapsed
                $progressPct = [Math]::Round(($deviceData.LastValue * 100) / $totalCombinations, 3)
                Write-Host -NoNewLine "Trying: $code | Attempt: $attempts | Progress: $progressPct% | Est. remaining: $remaining`r"
            }
            else {
                Write-Host -NoNewLine "Trying: $code | Attempts: $attempts | Elapsed: $([Math]::Floor($elapsed))s`r"
            }
            
            # Save progress periodically
            if ($attempts % 100 -eq 0) {
                Write-DeviceData -DeviceFile $devFile -DeviceData $deviceData
            }
        }
    }
}
finally {
    # Make sure we save progress if the script is terminated
    Write-DeviceData -DeviceFile $devFile -DeviceData $deviceData
}

Write-Host "Bootloader unlock complete!" -ForegroundColor Green
#endregion
#endregion

# Clear the screen
Clear-Host

# Function to read device data from the file
function Read-DevFile {
    param($DevFile)
    if (Test-Path $DevFile) {
        $content = Get-Content $DevFile
        foreach ($line in $content) {
            if ($line -match '^(.*?)=(.*)$') {
                $key = $matches[1]
                $value = $matches[2]
                switch ($key) {
                    'code_type' { $script:code_type = $value }
                    'code_length' { $script:code_length = [int]$value }
                    'last_value' { $script:last_value = [int64]$value }
                }
            }
        }
    }
}

# Function to write device data to the file
function Write-DevFile {
    param($DevFile)
    $data = @(
        "code_type=$code_type"
        "code_length=$code_length"
        "last_value=$last_value"
    )
    $data | Set-Content $DevFile
}

# Function to convert a number to a code string based on the character set
function NumberToCode {
    param($num, $length)
    $base = $charset.Length
    $code = ''
    while ($code.Length -lt $length) {
        $index = $num % $base
        $code = $charset[$index] + $code
        $num = [math]::Floor($num / $base)
    }
    return $code
}

# Get the current device name
$devicesOutput = & fastboot devices
if ($devicesOutput) {
    $devices = $devicesOutput -split "`n" | ForEach-Object { $_.Split("`t")[0] }
    $device = $devices[0]
    Write-Host "Current device: $device"
} else {
    Write-Host "No devices found."
    exit
}

$devfile = ".\${device}.dat"

# If device data file doesn't exist, prompt for code type and length
if (-Not (Test-Path $devfile)) {
    while ($true) {
        $code_type = Read-Host "Does the device use numeric or alphanumeric codes? (n/a)"
        if ($code_type -match '^(n|a|numeric|alphanumeric)$') {
            if ($code_type -eq 'n') { $code_type = 'numeric' }
            if ($code_type -eq 'a') { $code_type = 'alphanumeric' }
            break
        } else {
            Write-Host "Please enter 'n' for numeric or 'a' for alphanumeric."
        }
    }
    $code_length = Read-Host "Enter code length"
    $code_length = [int]$code_length
    $last_value = 0
    Write-DevFile $devfile
} else {
    Read-DevFile $devfile
}

# Set character set based on code type
if ($code_type -eq 'numeric') {
    $charset = '0123456789'
} elseif ($code_type -eq 'alphanumeric') {
    $charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
} else {
    Write-Host "Invalid code type: $code_type"
    exit
}

# Register an event to save data on script exit
Register-EngineEvent PowerShell.Exiting -Action {
    Write-DevFile $devfile
}

try {
    while ($true) {
        $code = NumberToCode $last_value $code_length

        # Try to unlock the device
        $output = & fastboot oem unlock $code 2>&1

        # Check if the unlock was successful
        if (-Not ($output -match 'fail(ed|ure)?')) {
            Write-Host "`nYour unlock code is: $code"
            break
        }

        # Display the current attempt
        Write-Host -NoNewline "Trying code: $code`r"

        $last_value++
        Write-DevFile $devfile
    }
}
finally {
    Write-DevFile $devfile
}

# Function to create a visual progress bar
function Show-ProgressBar {
    param (
        [int]$current,
        [int]$total,
        [string]$message
    )
    # Calculate the percentage of progress
    $progress = [math]::Round(($current * 100) / $total, 2)
    $done = [math]::Round(($progress * 4) / 10)
    $left = 40 - $done
    $fill = "#" * $done
    $empty = "-" * $left
    # Display the progress bar
    Write-Host -NoNewline "`rKey $current $message [$fill$empty] $progress%"
}

# Function to save the current progress to a file
function Save-Progress {
    param (
        [string]$value,
        [string]$deviceFile
    )
    Write-Output "Saving..."
    Set-Content -Path $deviceFile -Value $value
}

# Get the device name from fastboot and print it out
$devices = & fastboot devices
$device = $devices[0]
Write-Output "Current device: $device"

# Create a file name based on the device name
$devfile = "./$device.dat"

# Check if there's a file with previous progress, otherwise start from a default value
if (-Not (Test-Path -Path $devfile)) {
    $value = 1000000000000000
}
else {
    $value = Get-Content -Path $devfile
}

try {
    while ($true) {
        $output = & fastboot oem unlock $value 2>&1

        if (-Not ($output -match "(?i)fail(ed|ure)?")) {
            # If the unlock code is found
            Write-Output "Your unlock code is: $value"
            break
        }

        # Update the progress bar
        Show-ProgressBar -current $value -total 9999999999999999 -message $output[1]
        # Increment the value for the next attempt
        $value++
    }
}
finally {
    Save-Progress -deviceFile $devfile -value $value
}

# Function to create a visual progress bar
function Show-ProgressBar {
    param (
        [int]$currentValue,
        [int]$maximumValue
    )
    # Calculate the percentage of progress
    $progress = [math]::Round(($currentValue / $maximumValue) * 100)
    
    # Display the progress bar using Write-Progress
    Write-Progress -Activity "Unlocking Device" -Status "Key $currentValue" -PercentComplete $progress
}

# Function to save the current value to a file
function Save-Progress {
    param (
        [string]$value,
        [string]$deviceFile
    )
    Write-Host "Saving..."
    $value | Out-File $deviceFile
}

# Gracefully handle script exit
trap {
    Save-Progress -value $global:value -deviceFile $global:devfile
    exit
}

# Get the device name from fastboot and print it out
$device = (fastboot devices)[0]
Write-Host "Current device: $device"

# Create a file name based on the device name
$devfile = "./${device}.dat"

# Check if there's a file with previous progress, otherwise start from a default value
if (!(Test-Path $devfile)) {
    $global:value = 1000000000000000
} else {
    $global:value = Get-Content $devfile
}

# Loop until the unlock code is found or the maximum value is reached
while ($true) {
    # Attempt to unlock the device with the current value as the unlock code
    $output = fastboot oem unlock $global:value 2>&1
    if ($output[1] -notmatch "FAILED") {
        # If the unlock code is found
        Write-Host "Your unlock code is: $global:value"
        break
    }
    # Update the progress bar
    Show-ProgressBar -currentValue $global:value -maximumValue 9999999999999999
    # Increment the value for the next attempt
    $global:value++
}

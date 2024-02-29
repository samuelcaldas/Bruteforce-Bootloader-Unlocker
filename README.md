# Bruteforce Bootloader Unlocker

This project provides scripts to attempt unlocking the bootloader of Android devices using fastboot. It supports both Linux and Windows (PowerShell) environments.

## Requirements

- A computer running Linux or Windows with PowerShell.
- Fastboot and ADB installed and included in your system's PATH environment variable.
- USB debugging enabled on your Android device.

## Installation

1. Clone the repository or download the latest release.
2. Ensure that ADB and Fastboot are installed on your system:
   - For Linux, you can typically install these tools from your distribution's package manager.
   - For Windows, download the platform tools from the Android developer website and add the directory to your PATH.

## Usage

### Linux

1. Connect your device to your computer via a USB cable.
2. Open a terminal and navigate to the script's directory.
3. Run `chmod +x bootloader_unlocker` to make the script executable.
4. Execute the script with `./bootloader_unlocker`.

### Windows (PowerShell)

1. Connect your device to your computer via a USB cable.
2. Open PowerShell and navigate to the script's directory.
3. Run `.\bootloader_unlocker.ps1`.

The script will attempt different unlock codes until it finds the correct one or reaches the maximum value. The current value is saved in a persistent file named after your device's serial number, allowing you to resume the process later.

## Disclaimer

This script is experimental and for educational purposes only. Use it at your own risk. The author is not responsible for any damage or data loss that may occur as a result of using this script.

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) for details.

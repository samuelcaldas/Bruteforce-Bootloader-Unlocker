# Bruteforce Bootloader Unlocker

This project provides scripts to attempt unlocking the bootloader of Android devices using Fastboot. It supports both Linux and Windows (PowerShell) environments, featuring configurable code types and persistent device-specific settings to enhance usability and effectiveness.

## Features

- **Cross-Platform Support:** Compatible with Linux and Windows (PowerShell).
- **Configurable Code Types:** Supports both numeric and alphanumeric unlock codes.
- **Persistent Settings:** Stores device-specific configurations and the last attempted unlock code, allowing the process to resume seamlessly.
- **Dynamic Code Generation:** Generates unlock codes based on user-defined character sets and code lengths.
- **Graceful Exit Handling:** Saves progress automatically upon exit or interruption.
- **User-Friendly Prompts:** Guides users through initial setup with clear prompts for configuration.

## Requirements

- **For Both Linux and Windows:**
  - A computer with a USB port.
  - Fastboot and ADB installed and included in your system's PATH environment variable.
  - USB debugging enabled on your Android device.

- **For Windows:**
  - PowerShell installed (version 5.0 or higher is recommended).

## Installation

1. **Clone the Repository:**
   ```bash
   git clone https://github.com/samuelcaldas/bruteforce-bootloader-unlocker.git
   cd bruteforce-bootloader-unlocker
   ```

2. **Ensure Fastboot and ADB are Installed:**
   - **Linux:**
     - Install via your distribution's package manager. For example, on Debian-based systems:
       ```bash
       sudo apt-get update
       sudo apt-get install android-tools-adb android-tools-fastboot
       ```
   - **Windows:**
     - Download the [Android SDK Platform Tools](https://developer.android.com/studio/releases/platform-tools) from the Android developer website.
     - Extract the downloaded ZIP file.
     - Add the extracted directory to your system's PATH environment variable:
       - Press `Win + X` and select **System**.
       - Click on **Advanced system settings**.
       - Click **Environment Variables**.
       - Under **System variables**, find and select **Path**, then click **Edit**.
       - Click **New** and add the path to the extracted Platform Tools directory.
       - Click **OK** to save changes.

## Usage

### Linux

1. **Connect Your Device:**
   - Use a USB cable to connect your Android device to your computer.
   - Ensure that USB debugging is enabled on your device.

2. **Open Terminal and Navigate to the Script's Directory:**
   ```bash
   cd path/to/bruteforce-bootloader-unlocker
   ```

3. **Make the Script Executable:**
   ```bash
   chmod +x bootloader_unlocker
   ```

4. **Run the Script:**
   ```bash
   ./bootloader_unlocker
   ```

5. **Follow the Prompts:**
   - On the first run for a device, you'll be prompted to specify whether the unlock code is numeric (`n`) or alphanumeric (`a`), and to enter the length of the unlock code.
   - The script will store these settings in a file named after your device's serial number (e.g., `device123.dat`) for future runs.

6. **Unlock Process:**
   - The script will attempt different unlock codes based on your configuration.
   - Progress is displayed in the terminal, and the current state is saved automatically.
   - If interrupted, you can resume the process by running the script again.

### Windows (PowerShell) ALPHA!!!

1. **Connect Your Device:**
   - Use a USB cable to connect your Android device to your computer.
   - Ensure that USB debugging is enabled on your device.

2. **Open PowerShell and Navigate to the Script's Directory:**
   ```powershell
   cd C:\path\to\bruteforce-bootloader-unlocker
   ```

3. **Set Execution Policy (If Necessary):**
   - To allow the script to run, you may need to adjust the execution policy:
     ```powershell
     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
     ```

4. **Run the Script:**
   ```powershell
   .\bootloader_unlocker.ps1
   ```

5. **Follow the Prompts:**
   - Similar to the Linux version, you'll be prompted to specify the code type and length on the first run for each device.
   - Configuration is saved in a device-specific `.dat` file for future executions.

6. **Unlock Process:**
   - The script will attempt different unlock codes based on your configuration.
   - Progress is displayed in the PowerShell window, and the current state is saved automatically.
   - If interrupted, you can resume the process by running the script again.

## Script Configuration and Persistence

- **Device-Specific Configuration:**
  - Upon the first run for a device, the script prompts for:
    - **Code Type:** Whether the unlock codes are numeric or alphanumeric.
    - **Code Length:** The length of the unlock codes.
  - These settings are stored in a file named after your device's serial number (e.g., `device123.dat`), ensuring that you don't need to reconfigure settings for the same device in future runs.

- **Progress Saving:**
  - The script saves the last attempted unlock code in the configuration file.
  - This allows the script to resume from where it left off if interrupted.

## Disclaimer

**This script is experimental and for educational purposes only. Use it at your own risk. The author is not responsible for any damage or data loss that may occur as a result of using this script.**

**Legal and Ethical Considerations:**
- Ensure you have the legal right and permission to unlock the device.
- Unauthorized access to devices may be illegal and unethical.
- Repeated failed attempts to unlock a device may trigger security measures or permanently lock the device.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please fork the repository and submit a pull request with your enhancements or bug fixes.

## Support

If you encounter any issues or have questions, feel free to open an issue on the [GitHub repository](https://github.com/samuelcaldas/bruteforce-bootloader-unlocker/issues).

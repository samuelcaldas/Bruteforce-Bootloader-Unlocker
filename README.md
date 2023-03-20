# Bruteforce Bootloader Unlocker

This is a bash script that tries to unlock the bootloader of Android devices using fastboot.

## Requirements

- Linux operating system
- Fastboot installed
- USB debugging enabled on your device
- A persistent file named after your device serial number

## Usage

1. Connect your device to your computer via USB cable
2. Run `chmod +x bootloader_unlocker` to make the script executable
3. Run `./bootloader_unlocker` to start the bruteforce process
4. The script will try different unlock codes until it finds the correct one or reaches the maximum value (9999999999999999)
5. The script will save the current value in a persistent file every time it exits, so you can resume from where you left off
6. If the script finds your unlock code, it will display it on the screen and exit

## Disclaimer

This script is for educational purposes only. Use it at your own risk. I am not responsible for any damage or data loss that may occur as a result of using this script.

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) for details.

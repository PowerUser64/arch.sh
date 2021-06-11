# arch.sh
arch.sh is an install script for Arch Linux. What is unique about this install
script when compared to others is its use of the BTRFS filesystem for easy
system backups. This script is almost fully automated, with the only needed
user input being the password (needs to be typed 3 times in total). Other than
that, this script is configured entirely through the options at the top of the
script.

## What this does
This script installs Arch Linux, the Gnome desktop environment, and sets up 
BTRFS snapshots with [snapper](http://snapper.io/).

This is a pretty opinionated install, as it goes as far as to attempt to 
modify the dconf of the user, to set some sensible defaults. This is also 
intended to be a mostly automated install. Aside from entering your password 
(hopefully even this will be changed soon), all you need to do is watch the
text on the TTY fly by on the screen, as you think about how much of a
hacker you are for installing arch linux.

## Usage
0. Boot in to your Arch Linux install environment (live CD/USB)
1. Download this script using `curl -O git.io/JOANo`
2. Use your favorite text editor to change the configuration variables in the 
first few lines
3. Run the script with `bash arch.sh`
   - Create a password when the script asks for it
   - When installing an AUR helper (to make snapshots appear in the grub boot 
menu), you will be asked for your password once more
4. Reboot and enjoy your new Arch Linux installation!
5. Optional 5th step: run the automatically-created dconf script (`~/dconf.sh`)
to get some sensible defaults in your system configuration (this step will
hopefully be fully automated at some point)

## Contributing
Contributions are more than welcome! Please submit changes in a pull request 
with a clear list of what you've done.

### Coding style
Start reading the code and you'll get the hang of it, but here are some notes:
- Variables must be uppercase
- Functions must be lowercase
- Check your shell scripts with [ShellCheck](https://www.shellcheck.net/)
before submitting.
- Test your modified script in a VM to test it
 

#!/bin/bash
###
# Author: Blake North (PowerUser64)
# File name: arch.sh
# File purpose: install Arch Linux and the Gnome desktop environment on the BTRFS filesystem
#
# LICENSE: GNU GPLv3
###

# Shellcheck things. Debug only
# ignore the "modification" of variable in subshell (x2)
# shellcheck disable=SC2030
# shellcheck disable=SC2031

################################
## User Configuration Section ##
################################
# Partitions (set them up before you run the script)
ROOT='CHANGEME'                  # ex: /dev/sda3
BOOT='CHANGEME'                  # if you're installing Arch alongside another OS, make sure to backup your existing boot partition or make a new one for this
SWAP='CHANGEME'                  # set to a blank string to disable
MNT='/mnt'                       # the folder all partitions will be mounted to

# Installation settings
USER_TO_ADD='arch-user'          # needs to begin with a letter, be all lowercase, have no hyphens, and no underscores
HOSTNAME='archlinux'
BOOTLOADER_ID='archlinux-btrfs'  # not really sure what the requirements for this one are, but you probably shouldn't get too adventurous
MIRROR_COUNTRY='United States'   # see `reflector --list-countries` for a list of countries
TIME_ZONE='America/Los_Angeles'  # see `timedatectl list-timezones` for a list of timezones
LOCALE='en_US.UTF-8'             # see /etc/locale.gen for a list of locales (usually language_COUNTRY.charset)
KEYMAP='us'                      # see `localectl list-keymaps` for a list of keymaps
LAPTOP=1                         # if you are installing on a laptop, set this to 1 to install power management tools

# Additional installation settings
DCONF_MODS_BASIC=1               # (recommended to leave on) Some basic modifications to GNOME, such as enabling shell extensions installed by the script
DCONF_MODS_PLUS=0                # Some more opinionated dconf tweaks, such as dark theme and 12-hour clock
DCONF_MODS_KEY_BINDS=0           # set to 1 to apply some modifications to the default key bindings (review them below first, they're about at line 400)
AUR_HELPER=1                     # Whether to install an AUR helper (paru by default)

# TODO: figure out how to make all parts of the post-install script run without rebooting
# TODO: add make color optional (always, auto, never)

# Colors to make things look nice
   Red=$(tput setaf 1)
 Green=$(tput setaf 2)
  Cyan=$(tput setaf 6)
Yellow=$(tput setaf 11)
    NC=$(tput sgr0) # No Color

# makes it easier for the user to see what's happening, also makes it easier to debug ;)
pause() {
   sleep 0.5
}

# Takes a parameter that is the line number the error occurred on
error() {
   typewriter "An ${Red}error${NC} occurred on line number ${Red}${1}${NC}"
   exit
}

TEXT_DELAY='0.007' # the default time to wait between printing characters
# Type characters out one at a time (with a newline at the end)
typewriter() {
   text="$1"
   # make the delay optional
   [ -z ${2+x} ] && delay="${TEXT_DELAY}" || delay="$2"

   for i in $(seq 0 "${#text}") ; do
      echo -n "${text:$i:1}"
      sleep "${delay}"
   done
   echo
}
# Type characters out one at a time (without a newline at the end)
typewritern() {
   text="$1"
   # make the delay optional
   [ -z ${2+x} ] && delay="$TEXT_DELAY" || delay="$2"

   for i in $(seq 0 "${#text}") ; do
      echo -n "${text:$i:1}"
      sleep "${delay}"
   done
}

if [ -f "$ROOT" ] || [ -f "$BOOT" ] || { [ -z "$SWAP" ] && [ -f "$SWAP" ]; } then
   echo "${Red}Error${NC}: one or more of the specified drive partitions does not exist. Please ${Green}check the configuration${NC}."
   exit 1
fi

# Check if the computer is connected to the internet
typewriter "Checking for ${Cyan}internet${NC} access..."
if ! ping -q -c 2 -W 1 google.com > /dev/null; then
   typewriter "${Red}This script needs internet access${NC}. Please use '${Green}iwctl station <interface> connect <SSID>${NC}' to connect to the internet."
   exit 1
else
   typewriter "The system is ${Green}connected${NC} to the internet!"
fi
sleep 0.2 # systemd likes to chime in here and say that ntp time is on or something, so pause to avoid split lines

# Debug
# :<<\#_EOF

timedatectl set-ntp true
if ! [ -f ".mirrors_updated" ]; then # Don't refresh mirrors more than once if the script is run multiple times
   typewriter "${Green}Updating mirrors${NC} before continuing"
   typewriter "(${Green}this may take a bit${NC}, but it will ensure your downloads work)..."

   reflector \
      -c "$MIRROR_COUNTRY" \
      --protocol https \
      --threads 4 \
      --age 8 \
      --download-timeout 4 \
      --connection-timeout 4 \
      --sort rate \
      --save /etc/pacman.d/mirrorlist \
      > /dev/null 2>&1 || error "$LINENO" &&
      touch .mirrors_updated # Don't refresh mirrors more than once if the script is run multiple times

   typewriter "Mirror update ${Green}complete${NC}"
fi

########################################
##                                    ##
##   Setup drives (aside from swap)   ##
##                                    ##
########################################

# format drives
typewriter "This will ${Red}FORMAT${NC} the partitions you specified ($([ -n "${SWAP}" ] && echo -n "${Red}${SWAP}${NC}, ${Red}${ROOT}${NC}," || echo -n "${Red}${ROOT}${NC}") and ${Red}${BOOT}${NC})" 0.03
typewriter "Press enter if you are ${Red}certain${NC} you want to format these devices" 0.03
# shellcheck disable=SC2162
read
typewriter "Formatting $([ -n "${SWAP}" ] && echo -n "${Red}${SWAP}${NC}, ${Red}${ROOT}${NC}," || echo -n "${Red}${ROOT}${NC}") and ${Red}${BOOT}${NC} in 5 seconds" && sleep 6 # give the user extra time to cancel on purpose
umount -l "$MNT" # unmount the target so the script can be run more than once

# Setup the swap partition if the user specified one above
if [ -z "${SWAP}" ];then (mkswap "${SWAP}" && swapon "${SWAP}") > /dev/null 2>&1 || error $LINENO;fi
mkfs.fat -F32 "${BOOT}" || error "$LINENO"
mkfs.btrfs -f "${ROOT}" || error "$LINENO"
echo "${Green}Done!${NC}"
pause

typewriter "Creating ${Green}sub-volumes${NC}..."
mount "${ROOT}" "$MNT"
# create all sub volumes
btrfs sub create "$MNT/@"           || error "$LINENO"
btrfs sub create "$MNT/@log"        || error "$LINENO"
btrfs sub create "$MNT/@home"       || error "$LINENO"
btrfs sub create "$MNT/@cache"      || error "$LINENO"
btrfs sub create "$MNT/@snapshots"  || error "$LINENO"
echo "${Green}Done!${NC}"
umount "$MNT" || error "$LINENO"
pause

# mount all sub volumes
typewriter "${Green}Mounting${NC} sub-volumes..."
mount -o noatime,compress=lzo,space_cache=v2,discard=async,X-mount.mkdir,subvol=@            "${ROOT}" /mnt             || error "$LINENO"
mount -o noatime,compress=lzo,space_cache=v2,discard=async,X-mount.mkdir,subvol=@log         "${ROOT}" /mnt/var/log     || error "$LINENO"
mount -o noatime,compress=lzo,space_cache=v2,discard=async,X-mount.mkdir,subvol=@home        "${ROOT}" /mnt/home        || error "$LINENO"
mount -o noatime,compress=lzo,space_cache=v2,discard=async,X-mount.mkdir,subvol=@cache       "${ROOT}" /mnt/var/cache   || error "$LINENO"
mount -o noatime,compress=lzo,space_cache=v2,discard=async,X-mount.mkdir,subvol=@snapshots   "${ROOT}" /mnt/.snapshots  || error "$LINENO"

typewriter "Mounting boot (${Red}${BOOT}${NC}) to $MNT/boot/efi"
mount -o X-mount.mkdir "$BOOT" "$MNT/boot/efi" || error "$LINENO"
pause

###########################################
##                                       ##
##   Modifying the install starts here   ##
##                                       ##
###########################################

# pacstrap
typewriter "pacstrap time"
pause
pacstrap "$MNT" base linux linux-firmware "${EDITOR}" amd-ucode || error "$LINENO"
genfstab -U "$MNT" >> "$MNT/etc/fstab" || error "$LINENO"
echo "${Green}Done!${NC}"
pause

# Locales and date section
typewriter "Setting system time..."
arch-chroot "$MNT" ln -sf /usr/share/zoneinfo/America/Los_Angles /etc/localtime || error "$LINENO"
arch-chroot "$MNT" hwclock --systohc || error "$LINENO"
typewriter "Generating ${Green}locales${NC}"
# prepend the locale to the locale.gen file, rather than appending to it (just in case the user needs to find it)
arch-chroot "$MNT" bash -c "sed -i '1s;^;${LOCALE}\n;' /etc/locale.gen" || error "$LINENO"
arch-chroot "$MNT" echo "LANG=$LOCALE" > /etc/locale.conf || error "$LINENO"
arch-chroot "$MNT" locale-gen || error "$LINENO"
arch-chroot "$MNT" bash -c "echo 'KEYMAP=${KEYMAP}' >> /etc/vconsole.conf" || error "$LINENO"
echo "${Green}Done!${NC}"
pause

# Generate hostname
typewriter "Setting hostname to ${Green}${HOSTNAME}${NC}"
arch-chroot "$MNT" echo -n "$HOSTNAME" > /etc/hostname || error "$LINENO"
echo "${Green}Done!${NC}"
pause

# hosts file section
typewriter "Creating hosts file"
arch-chroot "$MNT" bash -c "(echo '127.0.0.1  localhost
127.0.1.1  ${HOSTNAME}
::1        localhost ip6-localhost ip6-loopback
ff02::1    ip6-allnodes
ff02::2    ip6-allrouters') >> /etc/hosts" || error "$LINENO"
echo "${Green}Done!${NC}"
pause

# install packages
# Remove TLP if you're not on a laptop
typewriter "Installing ${Green}packages${NC}!"
pause
# TODO: sort packages in to a meaningful order (maybe on separate lines too?)
arch-chroot "$MNT" bash -c "yes ''$'\n''y' | pacman -S --color=auto $([[ $LAPTOP ]] && echo 'tlp acpi acpi_call acpid') grub{,-btrfs} efibootmgr networkmanager network-manager-applet dialog mtools dosfstools git reflector base-devel linux-headers xdg-user-dirs xdg-utils gvfs gvfs-smb nfs-utils inetutils dnsutils bluez{,-utils} cups pipewire{,-{pulse,alsa,jack}} gst-plugin-pipewire libpulse openssh snapper rsync reflector ebtables firewalld sof-firmware nss-mdns os-prober ttf-joypixels" || error "$LINENO"
echo "${Green}Done!${NC}"
pause

# enable services
typewriter "Enabling ${Green}services${NC} with systemctl"
# This CAN be done all in one shot, but if it is, systemctl won't say what failed
arch-chroot "$MNT" systemctl enable NetworkManager.service  || error "$LINENO"
arch-chroot "$MNT" systemctl enable bluetooth.service       || error "$LINENO"
arch-chroot "$MNT" systemctl enable cups.service            || error "$LINENO"
arch-chroot "$MNT" systemctl enable reflector.timer         || error "$LINENO"
arch-chroot "$MNT" systemctl enable fstrim.timer            || error "$LINENO"
arch-chroot "$MNT" systemctl enable firewalld.service       || error "$LINENO"
if [[ $LAPTOP ]];then
   arch-chroot "$MNT" systemctl enable acpid.service        || error "$LINENO"
   arch-chroot "$MNT" systemctl enable tlp.service          || error "$LINENO"
fi

echo "${Green}Done!${NC}"

# bootloader
typewriter "Adding the ${Green}btrfs${NC} module to mkinitcpio.conf"
arch-chroot "$MNT" cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak || error "$LINENO"
arch-chroot "$MNT" sed -i '/MODULES/s/(/(btrfs /' /etc/mkinitcpio.conf || error "$LINENO" # add btrfs to the grub modules 
typewriter "Generating ${Green}initramfs${NC}"
arch-chroot "$MNT" mkinitcpio -p linux || error "$LINENO"
typewriter "Installing ${Green}grub${NC}"
arch-chroot "$MNT" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="$BOOTLOADER_ID" || error "$LINENO"
arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg || error "$LINENO"
# there should be an error in the command above. This is because there are no btrfs snapshots yet, and btrfs-grub wants there to be. Don't worry about it.
echo "${Green}Done!${NC}"
pause

# The "old" way of adding passwords which is better, so I'm using it.
# user setup
echo
typewriter "Time to ${Green}add a user${NC}!"
arch-chroot "$MNT" useradd -mG wheel "$USER_TO_ADD" || error "$LINENO"
typewriter "Please enter a password for user ${Green}${USER_TO_ADD}${NC}"
# use a loop to ensure the password is valid before continuing
while ! arch-chroot "$MNT" bash -c "passwd '$USER_TO_ADD'"; do
   echo
   typewriter "${Red}The password was not set${NC}, please try again"
   typewriter "Please enter a password for user ${Green}${USER_TO_ADD}${NC}"
done
pause

# sudoers
typewriter "Updating the ${Green}sudoers file${NC} for you..."
arch-chroot "$MNT" bash -c "(echo && echo '# From arch.sh: give all users in the wheel group sudo privilages' && 
   echo '%wheel ALL=(ALL) ALL') | sudo EDITOR='tee -a' visudo" > /dev/null 2>&1 || error "$LINENO"
pause

#################################################################
##                                                             ##
##   Post-install section (xorg, gnome, paru, and snapshots)   ##
##                                                             ##
#################################################################
echo
echo
echo "=========== Performing ${Green}post-install${NC} operations. ==========="

###############
##   Misc.   ##
###############
typewriter "Setting the ${Green}clock${NC}..."
arch-chroot "$MNT" timedatectl set-ntp true || error "$LINENO"
arch-chroot "$MNT" timedatectl set-timezone "$TIME_ZONE" || error "$LINENO"
pause

typewriter "Setting up ${Green}reflector${NC}..."
# reflector config file
arch-chroot "$MNT" bash -c "cat > /etc/xdg/reflector/reflector.conf << \##EOF
--save /etc/pacman.d/mirrorlist
--protocol https
--country '$MIRROR_COUNTRY'
--latest 8
--sort rate
##EOF
" || error "$LINENO"

# update the mirror list on the target system using the mirror list generated near the start of the script
cp -f /etc/pacman.d/mirrorlist ${MNT}/etc/pacman.d/mirrorlist || error "$LINENO"

##############
##   Paru   ##
##############
if [[ $AUR_HELPER ]];then
   typewriter "Installing ${Green}paru${NC}..."
   # I tried every way I could think of to get the user's password in to paru here, but I couldn't. Suggestions?
   arch-chroot "$MNT" bash -c "
   cd '/home/${USER_TO_ADD}'
   sudo -u '$USER_TO_ADD' mkdir git
   cd git
   pacman -S --color=auto --noconfirm --needed base-devel
   sudo -u '$USER_TO_ADD' git clone https://aur.archlinux.org/paru.git
   cd paru
   sudo -u '$USER_TO_ADD' makepkg --noconfirm -si
   " || error "$LINENO"
   ########################
   ##   More snapshots   ##
   ########################
   # display snapshots in grub
   arch-chroot "$MNT" sudo -u "$USER_TO_ADD" paru --noconfirm -S snap-pac-grub || error "$LINENO"
else
   typewriter "Skipping the ${Green}AUR helper${NC}"
fi

# Comment out this line to disable installing more things, like a Desktop environment
# :<<\#EODE
######################################
##   Gnome, graphics drivers, etc   ##
######################################
# needed
typewriter "Installing ${Green}graphical things${NC}!"
pause
arch-chroot "$MNT" pacman -S --color=auto --noconfirm xf86-video-amdgpu xorg gnome gdm gnome-tweaks gnome-software-packagekit-plugin pavucontrol || error "$LINENO"
arch-chroot "$MNT" systemctl enable gdm  || error "$LINENO"

# other graphical applications
arch-chroot "$MNT" pacman -S --color=auto --noconfirm gnome-shell-extension-appindicator \
   dconf-editor gparted tilix firefox libreoffice-fresh evince keepassxc kvantum-qt5 drawing \
   papirus-icon-theme \
   cantarell-fonts adobe-source-code-pro-fonts ttf-roboto \
   zsh \
|| error "$LINENO"
# TODO: install better libreoffice dictionaries

# AUR packages I like
if [[ $AUR_HELPER ]];then
   arch-chroot "$MNT" sudo -u "$USER_TO_ADD" paru -S --noconfirm \
      nautilus-admin nautilus-copy-path \
      pipewire-jack-dropin \
      firefox-extension-gnome-shell-integration gnome-shell-extension-middleclickclose \
      mkinitcpio-numlock \
      snapper-gui \
      vim-plug zplug nodejs \
   || error "$LINENO"
fi

arch-chroot "$MNT" sed -i '/HOOKS/s/(/(numlock /' /etc/mkinitcpio.conf || error "$LINENO" # enable numlock on boot (requires mkinitcpio-numlock, needs to go before encrypt)
arch-chroot "$MNT" sudo -u "$USER_TO_ADD" bash -c "echo 'export QT_STYLE_OVERRIDE=kvantum' >> ~/.profile" || error "$LINENO" # Enable kvantum as the Qt theme manager
chsh "$USER_TO_ADD" -s "$(which zsh)"

#EODE
# (end of desktop environment)

######################################################################
##                                                                  ##
##   Post-install one-time startup script and manual dconf script   ##
##                                                                  ##
######################################################################
# These scripts will enable snapshots, the firewall, and make a script that can
#    be manually run to set some sensible defaults to the dconf

#####################################
##   Dconf/Gnome settings tweaks   ## (this script must be run manually as of now)
#####################################

# Uncomment this line to disable creating a postins the dconf
# :<<\##EODC

# If you want to add your own dconf changes here, the way I got these is actually quite easy, here are the steps:
# 1- do a `dconf watch /` in your terminal
# 2- change the thing you want to add here (only do them one at a time so you know what does what)
# 3- go back to the terminal and copy paste the output in to a command similar to the ones here
# (note that you need to put quotes around the quotes as shown here, or it won't work)

[[ $DCONF_MODS_BASIC ]] && cat >> "$MNT/home/${USER_TO_ADD}/dconf.sh" << \##EODC
#!/bin/bash
sleep 1
# More sensible defaults for track pads (Recommended tweak)
dconf write /org/gnome/desktop/peripherals/touchpad/tap-to-click 'true'
dconf write /org/gnome/desktop/peripherals/touchpad/click-method \"'default'\"
dconf write /org/gnome/desktop/peripherals/touchpad/middle-click-emulation 'true'
# use RGB font aliasing, rather than greyscale (Recommended tweak)
dconf write /org/gnome/desktop/interface/font-antialiasing \"'rgba'\"

# enable shell extensions (Recommended, unless you don't want these)
dconf write /org/gnome/shell/enabled-extensions \"['appindicatorsupport@rgcjonas.gmail.com', 'middleclickclose@palo.tranquilli.gmail.com']\"
##EODC

[[ $DCONF_MODS_PLUS ]] && cat >> "$MNT/home/${USER_TO_ADD}/dconf.sh" << \##EODCP
# these are more personialized option, use them if you want
# use the 12-hour clock
dconf write /org/gnome/desktop/interface/clock-format  \"'12h'\"
dconf write /org/gtk/settings/file-chooser/clock-format  \"'12h'\"
# tell gnome tweaks to not tell me the 'the extensions tab has its own app now'
dconf write /org/gtk/tweaks/show-extensions-notice 'false'
# dark theme please
dconf write /org/gtk/desktop/gtk-theme \"'Adwita-dark'\"
dconf write /org/gtk/desktop/icon-theme \"'Papirus-Dark'\"
##EODCP

[[ $DCONF_MODS_KEY_BINDS ]] && cat >> "$MNT/home/${USER_TO_ADD}/dconf.sh" << \##EOKY
# Keybindings
# use alt tab to switch windows, rather than switch applications (Recommended tweak)
dconf write /org/gnome/desktop/wm/keybindings/switch-applications \"'@as []'\"
dconf write /org/gnome/desktop/wm/keybindings/switch-applications-backward \"'@as []'\"
dconf write /org/gnome/desktop/wm/keybindings/switch-windows \"['<Alt>Tab']\"
dconf write /org/gnome/desktop/wm/keybindings/switch-windows-backward \"['<Shift><Alt>Tab']\"
# ctrl+f11 to fullscreen any application
dconf write /org/gnome/desktop/wm/keybindings/toggle-fullscreen \"['<Primary>F11']\"
# change caps lock into escape and scroll lock into a compose key (a magic button that can combine characters. ex: compose a e = æ)
dconf write /org/gnome/desktop/input-sources/xkb-options \"['caps:escape', 'compose:sclk']\"
# ctrl+shift+esc = gnome-system-monitor (task manager)
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/binding \"'<Primary><Shift>Escape'\"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/command \"'gnome-system-monitor'\"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/name \"'System Monitor'\"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings \"['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']\"
# disable crtl+q so I don't accidentally press it instead of ctrl+w in my browser
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/binding \"'<Primary>q'\"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/command \"':'\"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/name \"'Disable Ctrl+Q'\"
dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings \"['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/']\"
dconf dump /
##EOKY
arch-chroot "$MNT" chmod +x "$MNT/home/${USER_TO_ADD}/dconf.sh"
arch-chroot "$MNT" chown "$USER_TO_ADD" "/home/${USER_TO_ADD}/dconf.sh"
#EODC

################################
##   Firewall and Snapshots   ##
################################

# To disable the creation of this script, uncomment this line:
# :<<\##EOPS

# Create a systemd service to run the script (this will get disabled and deleted by the script)
cat >> "$MNT/etc/systemd/system/post-install.service" << \#EOF 
[Unit]
Description=Running one-time initial configuration...

[Service]
ExecStart=/post-install.sh

[Install]
WantedBy=multi-user.target
#EOF

# post-install script to enable snapshots and setup the firewall
# if you know know how to do any of these things without a post-install script, please submit a pr :D
cat >> "$MNT/post-install.sh" << \#EOS
#!/bin/bash

[[ $DCONF_MODS ]] && chmod +x /home/${USER_TO_ADD}/dconf.sh
[[ $DCONF_MODS ]] && chown "$USER_TO_ADD" /home/${USER_TO_ADD}/dconf.sh
[[ $DCONF_MODS ]] && sudo -u "$USER_TO_ADD" bash -c "echo '~/dconf.sh' >> ~/.profile" # make the script run when the user logs in

# firewall (it causes errors if it's done outside the script)
firewall-cmd --add-port=1025-65535/tcp --permanent
firewall-cmd --add-port=1025-65535/udp --permanent
firewall-cmd --reload

###################
##   Snapshots   ##
###################
echo "Setting up snapshots..."
umount "/.snapshots"
rm -r "/.snapshots"
snapper -c root create-config /
btrfs subvolume delete "/.snapshots"
mkdir "/.snapshots"
mount -a
chmod 750 "/.snapshots"

# apply the arch wiki-recommended backup settings (keep a max of 5 hourly and 7 daily)
sed -i 's/ALLOW_USERS=""/ALLOW_USERS="$USER_TO_ADD"/g' /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_HOURLY="[0-9]*"/TIMELINE_LIMIT_HOURLY="5"/g'   /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_DAILY="[0-9]*"/TIMELINE_LIMIT_DAILY="7"/g'     /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_WEEKLY="[0-9]*"/TIMELINE_LIMIT_WEEKLY="0"/g'   /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_MONTHLY="[0-9]*"/TIMELINE_LIMIT_MONTHLY="0"/g' /etc/snapper/configs/root
sed -i 's/TIMELINE_LIMIT_YEARLY="[0-9]*"/TIMELINE_LIMIT_YEARLY="0"/g'   /etc/snapper/configs/root

# automatically backup the bootloader after installing software
mkdir /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/50-bootbackup.hook << \##EOF
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Path
Target = usr/lib/modules/*/vmlinuz

[Action]
Depends = rsync
Description = Backing up /boot...
When = PreTransaction
Exec = /usr/bin/rsync -a --delete /boot /.bootbackup
##EOF

echo "Cleaaning up..."
systemctl disable post-install.service
rm /post-install.sh
rm /etc/systemd/system/post-install.service
echo "Done!"
#EOS

# mark the post-install script as executable
   # This makes an error for some reason, but it doesn't work if I don't do it, so...
arch-chroot "$MNT" chmod +x "/etc/systemd/system/post-install.service"
arch-chroot "$MNT" chmod +x "/post-install.sh"
# make the script run on boot
arch-chroot "$MNT" systemctl enable post-install.service

##EOPS

echo
typewriter "${Green}Installation complete!${NC} You can reboot and enjoy your new Arch Linux installation ${Yellow}:)${NC}"

# Debug
#_EOF


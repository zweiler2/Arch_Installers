#!/bin/bash
# Arch Linux Install Script by zweiler2 TUI Edition

check_system() {
	### Check if EFI system ###
	if ls /sys/firmware/efi/efivars >/dev/null 2>&1; then
		EFI_SYSTEM=true
	else
		EFI_SYSTEM=false
	fi

	### Check if NVIDIA GPU user ###
	if [[ "$(lspci -v | grep VGA | sed -nE "s/.*(NVIDIA) .*/\1/p")" = "NVIDIA" ]]; then
		NVIDIA_USER=true
		if dialog --cr-wrap --title "NVIDIA GPU" --yesno "NVIDIA GPU found. These graphics cards were found on your system:\n\n$(lspci -k | grep -A 2 -E "(VGA|3D)")\n\nDo you want to install the nvidia proprietary driver?\nBy selecting \"no\" the open source \"nouveau\" driver will be installed." 0 0; then
			NVIDIA_PROPRIETARY=true
		else
			NVIDIA_PROPRIETARY=false
		fi
	else
		NVIDIA_USER=false
	fi

	## Check if AMD GPU user ###
	if [[ "$(lspci -v | grep VGA | sed -nE "s/.*(AMD) .*/\1/p")" = "AMD" ]]; then
		AMD_USER=true
		if dialog --cr-wrap --title "AMD GPU" --yesno "AMD GPU found. These graphics cards were found on your system:\n\n$(lspci -k | grep -A 2 -E "(VGA|3D)")\n\nDo you want to install the old non-Gallium3D mesa drivers (mesa-amber/mesa 21.3.9).\nSelect yes only if you have a really old GPU." 0 0; then
			MESA_AMBER=true
		else
			MESA_AMBER=false
		fi
	else
		AMD_USER=false
	fi

	### Check if Intel GPU user ###
	if [[ "$(lspci -v | grep VGA | sed -nE "s/.*(Intel) .*/\1/p")" = "Intel" ]]; then
		INTEL_USER=true
		if dialog --cr-wrap --title "Intel GPU" --yesno "Intel GPU found. These graphics cards were found on your system:\n\n$(lspci -k | grep -A 2 -E "(VGA|3D)")\n\nDo you want to install the old non-Gallium3D mesa drivers (mesa-amber/mesa 21.3.9).\nSelect yes only if you have a really old GPU." 0 0; then
			MESA_AMBER=true
		else
			MESA_AMBER=false
		fi
	else
		INTEL_USER=false
	fi
}

mounting() {
	### Mounting root partition ###
	if [ "$1" = "$ROOT_PARTITION" ]; then
		if ! grep "$ROOT_PARTITION" /etc/mtab; then
			if ! mount "$ROOT_PARTITION" /mnt; then
				echo "Error: Something went wrong when mounting root partition ($ROOT_PARTITION). Please try again!"
				read -r -p "Press Enter to exit..."
				exit 1
			else
				echo "Mounted $ROOT_PARTITION successfully"
			fi
		fi
	fi

	### Mounting home partition ###
	if [ "$1" = "$HOME_PARTITION" ]; then
		if ! grep "$HOME_PARTITION" /etc/mtab; then
			if ! mount --mkdir "$HOME_PARTITION" /mnt/home; then
				echo "Error: Something went wrong when mounting home partition ($HOME_PARTITION). Please try again!"
				read -r -p "Press Enter to exit..."
				exit 1
			else
				echo "Mounted $HOME_PARTITION successfully"
			fi
		fi
	fi

	### Mounting efi partition ###
	if [ "$1" = "$EFI_PARTITION" ]; then
		if ! grep "$EFI_PARTITION" /etc/mtab; then
			if ! mount --mkdir "$EFI_PARTITION" /mnt/efi; then
				echo "Error: Something went wrong when mounting efi partition ($EFI_PARTITION). Please try again!"
				read -r -p "Press Enter to exit..."
				exit 1
			else
				echo "Mounted $EFI_PARTITION successfully"
			fi
		fi
	fi
}

make_menu() {
	menu_list=()
	while read -r selector data; do
		menu_list+=("$selector" "$data")
	done <<<"$1"
}

make_language_menu() {
	language_menu_list=()
	while read -r selector; do
		language_menu_list+=("$selector" "$data")
	done <<<"$1"
}

make_checklist() {
	check_list=()
	while read -r selector; do
		check_list+=("$selector" "$data" "$off")
	done <<<"$1"
}

connect_to_wifi() {
	while true; do
		WIFI_DEVICE=$(iwctl device list | sed '1,4d' | sed 's/.$//' | sed 's/^ //' | cut -c6- | xargs | sed 's/\s.*$//')
		iwctl device "$WIFI_DEVICE" set-property Powered on
		WIFI_ADAPTER=$(iwctl device list | sed '1,4d' | sed 's/.$//' | sed 's/^ //' | cut -c6- | xargs | cut -d ' ' -f 4)
		iwctl adapter "$WIFI_ADAPTER" set-property Powered on
		iwctl station "$WIFI_DEVICE" scan
		make_menu "$(iwctl station "$WIFI_DEVICE" get-networks | tail -n +5 | head -n -1 | sed "s/\[1;30m//g" | sed "s/\[0m//g" | sed "s/\*\x1b.*/\*/g" | sed "s/\x1b//g" | cut -c 5-36 | sed "s/;90m> //g" | sed 's/^ *//')"
		SSID=$(dialog --stdout --title "WiFi" --menu "Select your WiFi" 0 0 0 "${menu_list[@]}")
		menu_list=()
		WIFI_PASS=$(dialog --stdout --insecure --title "WiFi" --passwordbox "Enter your WiFi password" 7 42)
		if iwctl --passphrase "$WIFI_PASS" station "$WIFI_DEVICE" connect "$SSID"; then
			break
		else
			if ! dialog --title "WiFi" --yesno 'Connection failed.\nDo you want to try again?' 0 0; then
				printf "No internet, no installation. Exiting...\n"
				exit 1
			fi
		fi
	done
	sleep 3
	check_internet_connection
}

check_internet_connection() {
	printf "Checking internet connectivity...\n"
	if ! ping -q -W 5 -c 3 archlinux.org >/dev/null; then
		printf "Cant't reach the Internet."
		if dialog --title "WiFi" --yesno 'Do you want to set up WiFi?' 0 0; then
			connect_to_wifi
		else
			printf "No internet, no installation. Exiting...\n"
			exit 1
		fi
	fi
}

exit_confirmation() {
	if dialog --title "EXIT" --defaultno --yesno "Are you sure you want to exit now?" 6 41; then
		echo "Exiting..."
		exit 1
	fi
}

make_menu "$(lsblk -lno name,size,model,serial,type | grep disk | sed s/disk//g | sed 's/  */ /g')"
DEVICELIST_ARRAY=("${menu_list[@]}")
menu_list=()

make_partlist_array() {
	make_menu "$(lsblk -lno name,size,model,serial,type | grep part | sed s/part//g | sed 's/  */ /g')"
	PARTLIST_ARRAY=("${menu_list[@]}")
	menu_list=()
}

information_gathering() {
	### Ask for keyboard layout while using the installer ###
	make_menu "$(localectl list-keymaps --no-pager)"
	while true; do
		if TEMP_KB_LAYOUT=$(dialog --stdout --title "Keyboard layout" --menu "Select a keyboard layout to use while using the installer" 0 0 0 "${menu_list[@]}"); then
			if [ -n "$TEMP_KB_LAYOUT" ]; then
				break
			else
				dialog --title "Keyboard layout" --msgbox "You didn't select a layout.\nPlease do so now." 6 31
			fi
		else
			exit_confirmation
		fi
	done
	menu_list=()
	loadkeys "$TEMP_KB_LAYOUT"
	sleep 3

	### Ask for the timezone ###
	TIMEZONE="$(curl --fail https://ipapi.co/timezone)"
	if ! dialog --title "Timezone" --yesno "Is the this your timezone?\n$TIMEZONE" 6 30; then
		make_menu "$(timedatectl list-timezones --no-pager)"
		while true; do
			if TIMEZONE=$(dialog --stdout --title "Timezone" --menu "Select your timezone" 0 0 0 "${menu_list[@]}"); then
				if [ -n "$TIMEZONE" ]; then
					break
				else
					dialog --title "Timezone" --msgbox "You didn't select a timezone.\nPlease do so now." 6 33
				fi
			else
				exit_confirmation
			fi
		done
		menu_list=()
	fi

	### Ask for languages ###
	make_checklist "$(cut </etc/locale.gen -c2- | tail -n +18 | sed '$ d' | sed 's/ *$//')"
	while true; do
		if LANGUAGES_ALL=$(dialog --stdout --separate-output --title "Language" --checklist "Select your desired languages" 0 0 0 "${check_list[@]}"); then
			if [ -n "$LANGUAGES_ALL" ]; then
				break
			else
				dialog --title "Language" --msgbox "You didn't select at least one language.\nPlease do so now." 6 44
			fi
		else
			exit_confirmation
		fi
	done
	check_list=()

	### Ask for main language ###
	make_language_menu "$LANGUAGES_ALL"
	while true; do
		if MAIN_LANGUAGE=$(dialog --stdout --title "Main language" --menu "Select your desired main language" 0 37 0 "${language_menu_list[@]}"); then
			if [ -n "$MAIN_LANGUAGE" ]; then
				break
			else
				dialog --title "Main language" --msgbox "You didn't select a main language.\nPlease do so now." 6 38
			fi
		else
			exit_confirmation
		fi
	done
	language_menu_list=()

	### Ask for keyboard layout ###
	make_menu "$(localectl list-keymaps --no-pager)"
	while true; do
		if KEYBOARD_LAYOUT=$(dialog --stdout --title "Keyboard layout" --menu "Select your desired keyboard layout" 0 0 0 "${menu_list[@]}"); then
			if [ -n "$KEYBOARD_LAYOUT" ]; then
				break
			else
				dialog --title "Keyboard layout" --msgbox "You didn't select a layout.\nPlease do so now." 6 31
			fi
		else
			exit_confirmation
		fi
	done
	menu_list=()

	### Ask for hostname ###
	NAME_REGEX="^[a-z][-a-z0-9]*\$"
	while true; do
		if ! HOSTNAME=$(dialog --stdout --title "Hostname" --inputbox 'Set your hostname (Name your PC!)' 7 37); then
			exit_confirmation
		elif [ "$HOSTNAME" = "root" ]; then
			dialog --title "Hostname" --msgbox "Setting your hostname to root is bad practice.\nPlease choose another." 6 50
		elif [ -z "$HOSTNAME" ]; then
			dialog --title "Hostname" --msgbox "Please set a hostname!" 5 26
		elif [ ${#HOSTNAME} -gt 63 ]; then
			dialog --title "Hostname" --msgbox "Hostname length must not exceed 63 characters!" 5 50
		elif [[ ! $HOSTNAME =~ $NAME_REGEX ]]; then
			dialog --title "Hostname" --msgbox "Invalid hostname \"$HOSTNAME\"\nHostname needs to follow these rules:\n\n- Must start with a lowercase letter.\n- May only contain lowercase letters, digits and hyphens." 9 61
		else
			break
		fi
	done

	### Ask for linux kernel ###
	while true; do
		if KERNEL=$(dialog --stdout --title "Kernel" --menu "Which linux kernel do you want to use?" 7 42 0 \
			1 "linux" \
			2 "linux-lts" \
			3 "linux-zen" \
			4 "linux-hardened" \
			5 "linux-rt" \
			6 "linux-rt-lts"); then
			if [ -n "$KERNEL" ]; then
				break
			else
				dialog --title "Kernel" --msgbox "You didn't select a kernel.\nPlease do so now." 6 31
			fi
		else
			exit_confirmation
		fi
	done
	case $KERNEL in
	1)
		KERNEL="linux"
		NVIDIA_PACKAGE="nvidia"
		;;
	2)
		KERNEL="linux-lts"
		NVIDIA_PACKAGE="nvidia-lts"
		;;
	3)
		KERNEL="linux-zen"
		NVIDIA_PACKAGE="nvidia-dkms"
		;;
	4)
		KERNEL="linux-hardened"
		NVIDIA_PACKAGE="nvidia-dkms"
		;;
	5)
		KERNEL="linux-rt"
		NVIDIA_PACKAGE="nvidia-dkms"
		;;
	6)
		KERNEL="linux-rt-lts"
		NVIDIA_PACKAGE="nvidia-dkms"
		;;
	esac

	### Ask for filesystem ###
	if dialog --title "Filesystem" --yesno "Do you want to use the btrfs filesystem?\n(EXT4 is the fallback)" 6 44; then
		EXT4=false
	else
		EXT4=true
	fi

	### Ask for SWAP file ###
	if dialog --title "SWAP" --yesno "Do you want to make a swapfile?\n(This is generally recommended to do)" 6 41; then
		CREATESWAPFILE=true
		while true; do
			if SWAPSIZE=$(dialog --stdout --title "SWAP" --menu "How big do you want your swapfile?\n(8GB is recommended)" 8 0 0 \
				1 "1GB" \
				2 "2GB" \
				3 "4GB" \
				4 "8GB" \
				5 "16GB"); then
				if [ -n "$SWAPSIZE" ]; then
					break
				else
					dialog --title "SWAP" --msgbox "You didn't select a size.\nPlease do so now." 6 29
				fi
			else
				exit_confirmation
			fi
		done
		case $SWAPSIZE in
		1) SWAPSIZE=1024 ;;
		2) SWAPSIZE=2048 ;;
		3) SWAPSIZE=4096 ;;
		4) SWAPSIZE=8192 ;;
		5) SWAPSIZE=16384 ;;
		esac
	else
		CREATESWAPFILE=false
	fi

	### Ask for multilib installation ###
	if dialog --title "Multilib repository" --yesno "Do you want to enable the pacman multilib repository?\n(You will probably need this, if you want to play games.)" 6 61; then
		MULTILIB_INSTALLATION=true
	else
		MULTILIB_INSTALLATION=false
	fi

	### Ask for os-prober ###
	if dialog --title "GRUB os-prober" --yesno "If you have other operating systems on your system you should enable os-prober.\nWith it you get a list of bootable systems at boottime.\nInstall os-prober?" 7 85; then
		INSTALL_OSPROBER=true
	else
		INSTALL_OSPROBER=false
	fi

	### Ask for AUR helper ###
	if dialog --title "AUR helper" --yesno "Do you want to have an AUR helper?" 5 38; then
		INSTALL_AUR_HELPER=true
		while true; do
			if AUR_HELPER=$(dialog --stdout --title "AUR helper" --menu "Which AUR helper do you want to have?\n" 7 41 0 \
				1 "Paru" \
				2 "Yay"); then
				if [ -n "$AUR_HELPER" ]; then
					break
				else
					dialog --title "AUR helper" --msgbox "You didn't select one.\nPlease do so now." 6 29
				fi
			else
				exit_confirmation
			fi
		done
	else
		INSTALL_AUR_HELPER=false
	fi

	### Setup chaotic AUR ###
	if dialog --title "Chaotic AUR" --yesno "Do you want to have access to the chaotic AUR?" 5 50; then
		INSTALL_CHAOTIC_AUR=true
	else
		INSTALL_CHAOTIC_AUR=false
	fi

	### Ask for a firewall ###
	if dialog --title "Firewall" --yesno "Install the Uncomplicated Firewall (UFW)?" 5 45; then
		INSTALL_FIREWALL=true
	else
		INSTALL_FIREWALL=false
	fi

	### Ask for openssh ###
	if dialog --title "OpenSSH" --yesno "Do you want to install OpenSSH for remote access?" 5 42; then
		INSTALL_OPENSSH=true
	else
		INSTALL_OPENSSH=false
	fi

	### Ask for antivirus ###
	if dialog --title "Antivirus" --yesno "Do you want to have an antivirus? (ClamTK)" 5 42; then
		INSTALL_ANTIVIRUS=true
	else
		INSTALL_ANTIVIRUS=false
	fi

	user_info_gathering
	partition_info_gathering

	### Ask for server install ###
	if dialog --title "Server install" --yesno "Do you want this system to be a server?\n(Plain minimal CLI system)" 6 43; then
		INSTALL_DESKTOP_ENVIRONMENT=false
		INSTALL_FLATPAK=false
		INSTALL_BLUETOOTH=false
		INSTALL_PRINTING=false
		INSTALL_PLYMOUTH=false
	else
		### Ask for Desktop Environment ###
		if dialog --title "Desktop Environment" --yesno "Do you want to install a Desktop Environment?" 5 49; then
			INSTALL_DESKTOP_ENVIRONMENT=true
			DESKTOP_TO_INSTALL=$(dialog --stdout --title "Desktop Environment" --menu "Which Desktop Environment do you want to install?" 9 53 1 \
				1 "KDE Plasma" \
				2 "GNOME")
		else
			INSTALL_DESKTOP_ENVIRONMENT=false
		fi

		### Ask for X11 keyboard layout ###
		if $INSTALL_DESKTOP_ENVIRONMENT; then
			pacman -Sy --noconfirm --needed xkeyboard-config
			make_menu "$(localectl list-x11-keymap-layouts --no-pager)"
			KEYBOARD_LAYOUT_X11=$(dialog --stdout --title "X11 keyboard layout" --menu "Select your desired X11 keyboard layout:" 0 43 0 "${menu_list[@]}")
			menu_list=()
		fi

		### Ask for flatpak support ###
		if dialog --title "Flatpak" --yesno "Do you want to have flatpak support?" 5 40; then
			INSTALL_FLATPAK=true
		else
			INSTALL_FLATPAK=false
		fi

		### Ask for bluetooth ###
		if dialog --title "Bluetooth" --yesno "Do you want to have bluetooth support?" 5 42; then
			INSTALL_BLUETOOTH=true
		else
			INSTALL_BLUETOOTH=false
		fi

		### Ask for printing ###
		if dialog --title "Printing" --yesno "Do you want to have printing support?" 5 41; then
			INSTALL_PRINTING=true
		else
			INSTALL_PRINTING=false
		fi

		### Setup plymouth ###
		if dialog --title "Plymouth" --yesno "Do you want to install plymouth?\n(Pretty boot screen with loading circle)" 6 45; then
			INSTALL_PLYMOUTH=true
		else
			INSTALL_PLYMOUTH=false
		fi
	fi
}

user_info_gathering() {
	### Setup password for root ###
	while true; do
		ROOTPASS=$(dialog --stdout --insecure --title "Account configuration" --passwordbox "Set root/system administrator password:" 7 42)
		if [ -z "$ROOTPASS" ]; then
			dialog --title "Account configuration" --msgbox "No password was set for user \"root\"!" 5 40
			break
		fi
		ROOTPASS_CONF=$(dialog --stdout --insecure --title "Account configuration" --passwordbox "Confirm your root password:" 7 30)
		if [ "$ROOTPASS" = "$ROOTPASS_CONF" ]; then
			break
		else
			dialog --title "Account configuration" --msgbox "Passwords do not match." 5 27
		fi
	done
	### Create user ###
	NAME_REGEX="^[a-z][-a-z0-9_]*\$"
	while true; do
		ARCHUSER=$(dialog --stdout --title "Account configuration" --inputbox "Enter username for this installation:" 7 41)
		if [ "$ARCHUSER" = "root" ]; then
			dialog --title "Account configuration" --msgbox "User root already exists." 5 29
		elif [ -z "$ARCHUSER" ]; then
			dialog --title "Account configuration" --msgbox "Please create a user!" 5 25
		elif [ ${#ARCHUSER} -gt 32 ]; then
			dialog --title "Account configuration" --msgbox "Username length must not exceed 32 characters!" 5 50
		elif [[ ! $ARCHUSER =~ $NAME_REGEX ]]; then
			dialog --title "Account configuration" --msgbox "Invalid username \"$ARCHUSER\"\nUsername needs to follow these rules:\n\n- Must start with a lowercase letter.\n- May only contain lowercase letters, digits, hyphens, and underscores." 9 75
		else
			break
		fi
	done
	### Setup password for user ###
	while true; do
		ARCHPASS=$(dialog --stdout --insecure --title "Account configuration" --passwordbox "Set password for \"$ARCHUSER\":" 7 40)
		if [ -z "$ARCHPASS" ]; then
			dialog --title "Account configuration" --msgbox "Please type password for user \"$ARCHUSER\"!" 5 50
		else
			ARCHPASS_CONF=$(dialog --stdout --insecure --title "Account configuration" --passwordbox "Confirm password for \"$ARCHUSER\":" 7 45)
			if [ "$ARCHPASS" = "$ARCHPASS_CONF" ]; then
				break
			else
				dialog --title "Account configuration" --msgbox "Passwords do not match." 5 27
			fi
		fi
	done
}

partition_info_gathering() {
	### Ask for automatic partitioning ###
	if dialog --title "Partitioning" --yesno "Do you want to manually partition your drive?\nIf you choose to manually partition you will get asked for your root, efi (if applicable) and (if you made one) home partition.\nWith the automatic partitioning you can only select a whole drive!" 8 70; then
		MANUAL_PARTITIONING=true
		dialog --title "Partitioning" --msgbox "Get your partitions fully ready so that a system can be installed! \nMeaning that the partitions have to be formated, set esp and boot flag (and labeled if you like) correctly!\nOpening a new bash instance so you can use whatever tools you want.\nWhen you're done type exit." 9 71
		bash

		### Ask for root partition ###
		make_partlist_array
		while true; do
			if ! ROOT_PARTITION=$(dialog --stdout --title "Select ROOT partition" --menu "Select your root partition" 0 0 0 "${PARTLIST_ARRAY[@]}"); then
				if dialog --title "Select ROOT partition" --defaultno --yesno "Do you want to launch a subshell for doing the partitioning again?" 6 41; then
					bash
				else
					exit_confirmation
				fi
			fi
			ROOT_PARTITION=$(echo "$ROOT_PARTITION" | cut -d ' ' -f 1)
			if [ -z "$ROOT_PARTITION" ]; then
				dialog --title "Select ROOT partition" --msgbox "You didn't select a root partition,\nplease do so now." 6 39
			else
				ROOT_PARTITION="/dev/${ROOT_PARTITION}"
				break
			fi
		done

		### Ask for efi partition ###
		make_partlist_array
		if $EFI_SYSTEM; then
			while true; do
				if ! EFI_PARTITION=$(dialog --stdout --title "Select EFI partition" --menu "Select your efi partition" 0 0 0 "${PARTLIST_ARRAY[@]}"); then
					if dialog --title "Select EFI partition" --defaultno --yesno "Do you want to launch a subshell for doing the partitioning again?" 6 41; then
						bash
					else
						exit_confirmation
					fi
				fi
				EFI_PARTITION=$(echo "$EFI_PARTITION" | cut -d ' ' -f 1)
				if [ -z "$EFI_PARTITION" ]; then
					dialog --title "Select EFI partition" --msgbox "You didn't select a efi partition,\nplease do so now." 6 39
				elif [[ "/dev/${EFI_PARTITION}" = "$ROOT_PARTITION" ]]; then
					dialog --title "Partitioning" --msgbox "This is your root partition. Choose another one..." 0 0
				elif [[ "/dev/${EFI_PARTITION}" != "$ROOT_PARTITION" ]]; then
					EFI_PARTITION="/dev/${EFI_PARTITION}"
					break
				fi
			done
		fi

		### Ask for home partition ###
		make_partlist_array
		if dialog --title "Partitioning" --yesno "Did you make a seperate /home partition?" 5 45; then
			CREATEHOMEPARTITION=true
			while true; do
				if ! HOME_PARTITION=$(dialog --stdout --title "Select HOME partition" --menu "Select your home partition" 0 0 0 "${PARTLIST_ARRAY[@]}"); then
					if dialog --title "Select HOME partition" --defaultno --yesno "Do you want to launch a subshell for doing the partitioning again?" 6 41; then
						bash
					else
						exit_confirmation
					fi
				fi
				HOME_PARTITION=$(echo "$HOME_PARTITION" | cut -d ' ' -f 1)
				if [ -z "$HOME_PARTITION" ]; then
					dialog --title "Select HOME partition" --msgbox "You didn't select a home partition,\nplease do so now." 6 39
				elif [[ "/dev/${HOME_PARTITION}" = "$ROOT_PARTITION" ]]; then
					dialog --title "Partitioning" --msgbox "This is your root partition. Choose another one..." 0 0
				elif [[ "/dev/${HOME_PARTITION}" = "$EFI_PARTITION" ]]; then
					dialog --title "Partitioning" --msgbox "This is your efi partition. Choose another one..." 5 55
				elif [[ "/dev/${HOME_PARTITION}" != "$ROOT_PARTITION" && "/dev/${HOME_PARTITION}" != "$EFI_PARTITION" ]]; then
					HOME_PARTITION="/dev/${HOME_PARTITION}"
					break
				fi
			done
		else
			CREATEHOMEPARTITION=false
		fi
	else
		MANUAL_PARTITIONING=false
		### Drive select ###
		while true; do
			DEVICE=$(dialog --stdout --title "Select disk" --menu "Select your disk to install Arch Linux to:" 0 0 0 "${DEVICELIST_ARRAY[@]}")
			INSTALLDEVICE="/dev/${DEVICE}"
			if [ ! -b "$INSTALLDEVICE" ]; then
				dialog --title "Partitioning" --msgbox "$DEVICE not found!" 5 22
			elif [ "$(lsblk "$DEVICE" | head -n2 | tail -n1 | grep disk >/dev/null 2>&1)" = "" ]; then
				if dialog --cr-wrap --defaultno --title "Partitioning" --yesno "WARNING: The following drive is going to be fully erased.\nALL DATA ON DRIVE ${INSTALLDEVICE} WILL BE LOST!\n\n$(lsblk -l -o NAME,MAJ:MIN,RM,SIZE,RO,TYPE,VENDOR,MODEL,SERIAL,MOUNTPOINT "${INSTALLDEVICE}")\n\nErase ${INSTALLDEVICE} and contine installation?" 0 0; then
					break
				else
					exit 1
				fi
			else
				dialog --title "Partitioning" --msgbox "$DEVICE is not of type disk!" 5 32
			fi
		done

		### Ask for existing EFI partition ###
		make_partlist_array
		if $EFI_SYSTEM; then
			if dialog --defaultno --title "EFI" --yesno 'Do you want to use an existing efi partition?' 0 0; then
				EFI_PARTITION_REUSE=true
				EFI_PARTITION=$(dialog --stdout --title "Select partition" --menu "Select your existing efi partition" 0 0 0 "${PARTLIST_ARRAY[@]}")
				EFI_PARTITION_SIZE=$(lsblk -lno name,size,type | grep part | sed s/part//g | sed 's/  */ /g' | grep "$EFI_PARTITION" | cut -d ' ' -f 2 | grep -Eo '[0-9]{1,4}') ### Puts out garbage if not in MB ###
				EFI_PARTITION="/dev/${EFI_PARTITION}"

				### Check if EFI partition is on same device ###
				if echo "$EFI_PARTITION" | grep "$INSTALLDEVICE"; then
					EFI_PARTITION_ON_SAME_DEVICE=true

				else
					EFI_PARTITION_ON_SAME_DEVICE=false
				fi
			else
				EFI_PARTITION_REUSE=false
			fi
		else
			EFI_PARTITION_REUSE=false
			EFI_PARTITION_ON_SAME_DEVICE=false
		fi

		### Ask for seperate /home partition ###
		while true; do
			if dialog --title "Partitioning" --yesno "Do you want to make a seperate /home partition?" 5 51; then
				CREATEHOMEPARTITION=true
				if echo "${DEVICE}" | grep -q -P "^/dev/(nvme|loop|mmcblk)"; then
					DISK_SIZE="$(parted "$INSTALLDEVICE" print | grep "Disk $INSTALLDEVICE" | cut -c20-)"
				else
					DISK_SIZE="$(parted "$INSTALLDEVICE" print | grep "Disk $INSTALLDEVICE" | cut -c16-)"
				fi
				ROOT_PARTITON_SIZE=$(dialog --stdout --title "Partitioning" --inputbox "The installdrive is $DISK_SIZE big.\nHow big do you want your root partiton? (in MB!) (eg 50000MB = 50GB)\nMore than 100GB and/or half the disk size is not recommended." 9 72)
				CONTINUE_WITH_OVERSIZED_ROOT_PARTITION=
				IS_A_NUMBER='^[0-9]+$'
				if [[ $ROOT_PARTITON_SIZE =~ $IS_A_NUMBER ]]; then
					DISK_SIZE=${DISK_SIZE//GB/}
					DISK_SIZE_INT=${DISK_SIZE%.*}
					DISK_SIZE_MB=$((DISK_SIZE_INT * 1000))
					HALF_DISK_SIZE_MB=$((DISK_SIZE_MB / 2))
					if [[ $ROOT_PARTITON_SIZE -gt $HALF_DISK_SIZE_MB ]]; then
						if dialog --title "Partitioning" --yesno "Root partition size is bigger than half of the installdisk size.\nThis is not recommended.\nAre you sure you want to continue?" 7 68; then
							break
						else
							CONTINUE_WITH_OVERSIZED_ROOT_PARTITION=false
						fi
					fi
					if [ -z "${CONTINUE_WITH_OVERSIZED_ROOT_PARTITION}" ]; then
						break
					fi
				else
					dialog --title "Partitioning" --msgbox "$ROOT_PARTITON_SIZE is not a number!" 5 35
				fi
			else
				CREATEHOMEPARTITION=false
				break
			fi
		done
	fi
}

auto_partitioning() {
	if ! dialog --cr-wrap --defaultno --title "Format confirmation" --yesno "WARNING: The following drive is going to be fully erased.\nALL DATA ON DRIVE ${INSTALLDEVICE} WILL BE LOST! \n\n$(lsblk -o NAME,MAJ:MIN,RM,SIZE,RO,TYPE,VENDOR,MODEL,SERIAL,MOUNTPOINT "${INSTALLDEVICE}" | sed "1d")\n\nThis is the last warning! \nErase ${INSTALLDEVICE} and begin installation?" 20 0; then
		dialog --sleep 5 --title "Format canceled" --infobox "Nothing has been written,\nbecause you have canceled the destructive install.\n\nExiting in 5 seconds..." 6 54
		echo "Destructive Install Canceled."
		exit 1
	fi

	### Unmount twice for good measure ###
	umount "$INSTALLDEVICE"* >/dev/null 2>&1
	umount -R -f /mnt >/dev/null 2>&1

	### Wiping disk ###
	sfdisk --delete "$INSTALLDEVICE"
	wipefs -a "$INSTALLDEVICE"
	if $EFI_SYSTEM; then
		parted "$INSTALLDEVICE" mklabel gpt
	else
		parted "$INSTALLDEVICE" mklabel msdos
	fi

	### Set partition layout ###
	if echo "${INSTALLDEVICE}" | grep -q -P "^/dev/(nvme|loop|mmcblk)"; then
		INSTALLDEVICE="${INSTALLDEVICE}p"
	fi

	if $EFI_SYSTEM && ! $EFI_PARTITION_REUSE; then
		efiPartNum=1
		rootPartNum=2
		efiStart=1
		efiEnd=$(("$efiStart" + 128))
		rootStart=$efiEnd
	elif $EFI_SYSTEM && $EFI_PARTITION_REUSE && ! $EFI_PARTITION_ON_SAME_DEVICE; then
		rootPartNum=1
		rootStart=1
	elif $EFI_SYSTEM && $EFI_PARTITION_REUSE && $EFI_PARTITION_ON_SAME_DEVICE; then
		rootPartNum=2
		rootStart=$EFI_PARTITION_SIZE
	else ### Legacy boot ###
		rootPartNum=1
		rootStart=3
	fi
	if $CREATEHOMEPARTITION; then
		rootEnd=$(("$rootStart" + "$ROOT_PARTITON_SIZE"))
		homePartNum=$(("$rootPartNum" + 1))
	fi

	### Actual partitioning ###
	if $EFI_SYSTEM; then
		if ! $EFI_PARTITION_REUSE; then
			parted "${INSTALLDEVICE}" mkpart esp fat32 "${efiStart}"M "${efiEnd}"M
			parted "${INSTALLDEVICE}" set "${efiPartNum}" boot on
			parted "${INSTALLDEVICE}" set "${efiPartNum}" esp on
			EFI_PARTITION="${INSTALLDEVICE}${efiPartNum}"
			yes | mkfs.vfat -F 32 -n EFI "${EFI_PARTITION}"
		fi
		if $CREATEHOMEPARTITION; then
			if $EXT4; then
				parted "${INSTALLDEVICE}" mkpart archlinux ext4 "${rootStart}"M "${rootEnd}"M # ROOT partition
				parted "${INSTALLDEVICE}" mkpart home ext4 "${rootEnd}"M 100%                 # HOME partition
				HOME_PARTITION="${INSTALLDEVICE}${homePartNum}"
				yes | mkfs.ext4 -L HOME "${HOME_PARTITION}"
			else
				parted "${INSTALLDEVICE}" mkpart archlinux btrfs "${rootStart}"M "${rootEnd}"M # ROOT partition
				parted "${INSTALLDEVICE}" mkpart home btrfs "${rootEnd}"M 100%                 # HOME partition
				HOME_PARTITION="${INSTALLDEVICE}${homePartNum}"
				yes | mkfs.btrfs -f -L HOME "${HOME_PARTITION}"
			fi
		else
			if $EXT4; then
				parted "${INSTALLDEVICE}" mkpart archlinux ext4 "${rootStart}"M 100% # ROOT partition
			else
				parted "${INSTALLDEVICE}" mkpart archlinux btrfs "${rootStart}"M 100% # ROOT partition
			fi
		fi
		if $EXT4; then
			ROOT_PARTITION="${INSTALLDEVICE}${rootPartNum}"
			yes | mkfs.ext4 -L ROOT "$ROOT_PARTITION"
		else
			ROOT_PARTITION="${INSTALLDEVICE}${rootPartNum}"
			yes | mkfs.btrfs -f -L ROOT "$ROOT_PARTITION"
		fi
	else
		if $CREATEHOMEPARTITION; then
			if $EXT4; then
				parted "${INSTALLDEVICE}" mkpart primary ext4 "${rootStart}"M "${rootEnd}"M # ROOT partition
				parted "${INSTALLDEVICE}" mkpart primary ext4 "${rootEnd}"M 100%            # HOME partition
				HOME_PARTITION="${INSTALLDEVICE}${homePartNum}"
				yes | mkfs.ext4 -L HOME "${HOME_PARTITION}"
			else
				parted "${INSTALLDEVICE}" mkpart primary btrfs "${rootStart}"M "${rootEnd}"M # ROOT partition
				parted "${INSTALLDEVICE}" mkpart primary btrfs "${rootEnd}"M 100%            # HOME partition
				HOME_PARTITION="${INSTALLDEVICE}${homePartNum}"
				yes | mkfs.btrfs -f -L HOME "${HOME_PARTITION}"
			fi
		else
			if $EXT4; then
				parted "${INSTALLDEVICE}" mkpart primary ext4 "${rootStart}"M 100% # ROOT partition
			else
				parted "${INSTALLDEVICE}" mkpart primary btrfs "${rootStart}"M 100% # ROOT partition
			fi
		fi
		if $EXT4; then
			ROOT_PARTITION="${INSTALLDEVICE}${rootPartNum}"
			yes | mkfs.ext4 -L ROOT "$ROOT_PARTITION"
		else
			ROOT_PARTITION="${INSTALLDEVICE}${rootPartNum}"
			yes | mkfs.btrfs -f -L ROOT "$ROOT_PARTITION"
		fi
		parted "${INSTALLDEVICE}" set "${rootPartNum}" boot on
	fi
}

base_os_install() {
	### Mounting filesystems ###
	mounting "$ROOT_PARTITION"
	if ! $EXT4; then
		btrfs sub cr /mnt/@
		btrfs sub cr /mnt/@tmp
		btrfs sub cr /mnt/@log
		btrfs sub cr /mnt/@pkg
		btrfs sub cr /mnt/@snapshots
		if ! $CREATEHOMEPARTITION; then
			btrfs sub cr /mnt/@home
		fi
		if $CREATESWAPFILE; then
			btrfs sub cr /mnt/@swap
		fi
		umount /mnt
		mount -o subvol=@ "${ROOT_PARTITION}" /mnt
		mkdir -p /mnt/{efi,var/log,var/cache/pacman/pkg,tmp,swap}
		mount -o subvol=@log "${ROOT_PARTITION}" /mnt/var/log
		mount -o subvol=@pkg "${ROOT_PARTITION}" /mnt/var/cache/pacman/pkg/
		mount -o subvol=@tmp "${ROOT_PARTITION}" /mnt/tmp
		if ! $CREATEHOMEPARTITION; then
			mount --mkdir -o subvol=@home "${ROOT_PARTITION}" /mnt/home
		fi
		if $CREATESWAPFILE; then
			mount -o subvol=@swap "${ROOT_PARTITION}" /mnt/swap
		fi
	fi
	if $EFI_SYSTEM; then
		mounting "$EFI_PARTITION"
	fi
	if $CREATEHOMEPARTITION; then
		mounting "$HOME_PARTITION"
	fi

	### Installing base packages ###
	sed -i 's/#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
	pacstrap -K /mnt base base-devel "$KERNEL" "${KERNEL}"-headers linux-firmware sudo bash-completion mtools dosfstools fwupd power-profiles-daemon cpupower btrfs-progs pacman-contrib
	sed -i 's/#ParallelDownloads/ParallelDownloads/' /mnt/etc/pacman.conf

	### Generate fstab ###
	printf "\nBase system installation done, generating fstab...\n\n"
	genfstab -U /mnt >/mnt/etc/fstab

	### Create SWAP file ###
	if $CREATESWAPFILE; then
		echo "Creating swapfile..."
		mkdir /mnt/swap
		if $EXT4; then
			dd if=/dev/zero of=/mnt/swap/swapfile bs=1M count="$SWAPSIZE" status=progress
			chmod 0600 /mnt/swap/swapfile
			mkswap -U clear /mnt/swap/swapfile
		else
			btrfs filesystem mkswapfile --size "$SWAPSIZE"m --uuid clear /mnt/swap/swapfile
		fi
		swapon /mnt/swap/swapfile
		echo /swap/swapfile none swap defaults 0 0 >>/mnt/etc/fstab
	fi

	### Set hwclock ###
	printf "\nSyncing HW clock\n\n"
	arch-chroot /mnt hwclock --systohc
	arch-chroot /mnt systemctl enable systemd-timesyncd

	### Set timezone ###
	arch-chroot /mnt ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime

	### Set locales ###
	echo "$LANGUAGES_ALL" | tr "|" "\n" >>/mnt/etc/locale.gen
	arch-chroot /mnt locale-gen
	touch /mnt/etc/locale.conf
	MAIN_LANGUAGE="$(echo "$MAIN_LANGUAGE" | cut -d' ' -f1)"
	echo "LANG=$MAIN_LANGUAGE" >>/mnt/etc/locale.conf

	### Set keyboard layout ###
	echo "KEYMAP=$KEYBOARD_LAYOUT" >>/mnt/etc/vconsole.conf

	### Set hostname ###
	echo "$HOSTNAME" >/mnt/etc/hostname

	### Enable fstrim.timer ###
	arch-chroot /mnt systemctl enable fstrim.timer

	### Set up pacman multilib ###
	if $MULTILIB_INSTALLATION; then
		arch-chroot /mnt sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
		arch-chroot /mnt pacman -Syyu --noconfirm
	fi

	### Create users ###
	printf "\nConfiguring user accounts..."
	printf "\nCreating user %s${ARCHUSER}...\n"
	echo -e "${ROOTPASS}\n${ROOTPASS}" | arch-chroot /mnt passwd root
	arch-chroot /mnt useradd --create-home "${ARCHUSER}"
	echo -e "${ARCHPASS}\n${ARCHPASS}" | arch-chroot /mnt passwd "${ARCHUSER}"
	echo "${ARCHUSER} ALL=(ALL) ALL" >/mnt/etc/sudoers.d/"${ARCHUSER}"
	chmod 0440 /mnt/etc/sudoers.d/"${ARCHUSER}"
	arch-chroot /mnt usermod -G wheel -a "${ARCHUSER}"

	### Set up hosts ###
	printf "Set up hosts...\n"
	{
		echo "127.0.0.1    localhost"
		echo "127.0.1.1    $HOSTNAME.localdomain $HOSTNAME"
		echo
		echo "# IPv6"
		echo "::1          localhost ip6-localhost ip6-loopback"
		echo "ff02::1 ip6-allnodes"
		echo "ff02::2 ip6-allrouters"
	} >>/mnt/etc/hosts

	### Set up pacman ###
	printf "Getting pacman ready...\n"
	arch-chroot /mnt pacman-key --init
	arch-chroot /mnt pacman -Syyu --noconfirm

	### Set up cpu microcode ###
	printf "\nInstalling microcodes...\n\n"
	arch-chroot /mnt pacman -S --noconfirm intel-ucode amd-ucode

	### Set up bootloader/GRUB ###
	printf "Installing bootloader...\n"
	mkdir /mnt/boot
	arch-chroot /mnt pacman -S --noconfirm grub
	if $EFI_SYSTEM; then
		arch-chroot /mnt pacman -S --noconfirm efibootmgr
	fi
	if ! $EXT4; then
		arch-chroot /mnt pacman -S --noconfirm grub-btrfs
	fi
	mkdir /mnt/etc/pacman.d/hooks 2>/dev/null
	if $EFI_SYSTEM; then
		if arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id="Arch-Linux" --removable; then
			arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
			printf "\nBootloader install successful\n"
			{
				echo "[Trigger]"
				echo "Operation=Upgrade"
				echo "Type=Package"
				echo "Target=grub"
				echo
				echo "[Action]"
				echo "Description=Reinstall and Update GRUB"
				echo "When=PostTransaction"
				echo "NeedsTargets"
				echo "Exec=/bin/sh -c 'grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=Arch-Linux --removable && sudo grub-mkconfig -o /boot/grub/grub.cfg'"
			} >/mnt/etc/pacman.d/hooks/grub.hook
		else
			printf "\nBootloader install failed!\n"
		fi
	else
		if arch-chroot /mnt grub-install --target=i386-pc "$INSTALLDEVICE"; then
			arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
			printf "\nBootloader install successful\n"
			{
				echo "[Trigger]"
				echo "Operation=Upgrade"
				echo "Type=Package"
				echo "Target=grub"
				echo
				echo "[Action]"
				echo "Description=Reinstall and Update GRUB"
				echo "When=PostTransaction"
				echo "NeedsTargets"
				echo "Exec=/bin/sh -c 'grub-install --target=i386-pc $INSTALLDEVICE && sudo grub-mkconfig -o /boot/grub/grub.cfg'"
			} >/mnt/etc/pacman.d/hooks/grub.hook
		else
			printf "\nBootloader install failed!\n"
		fi
	fi

	### Set up os-prober ###
	if $INSTALL_OSPROBER; then
		arch-chroot /mnt pacman -S --noconfirm os-prober
		sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /mnt/etc/default/grub
		arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
	fi

	### Set up flatpak ###
	if $INSTALL_FLATPAK; then
		case $DESKTOP_TO_INSTALL in
		1)
			arch-chroot /mnt pacman -S --noconfirm xdg-desktop-portal-kde flatpak
			;;
		2)
			arch-chroot /mnt pacman -S --noconfirm xdg-desktop-portal-gnome xdg-desktop-portal-gtk flatpak
			;;
		esac
	fi

	### Set up firewall ###
	if $INSTALL_FIREWALL; then
		arch-chroot /mnt systemctl disable iptables.service
		arch-chroot /mnt pacman -S --noconfirm ufw
		arch-chroot /mnt systemctl enable ufw.service
		arch-chroot /mnt ufw enable
		arch-chroot /mnt ufw default deny
		$INSTALL_OPENSSH && arch-chroot /mnt /ufw allow SSH
	fi

	### Set up networking ###
	arch-chroot /mnt pacman -S --noconfirm networkmanager
	arch-chroot /mnt systemctl enable NetworkManager.service
}

xorg_graphics_install() {
	### Set up Xorg ###
	arch-chroot /mnt pacman -S --noconfirm --needed xorg-server xorg-xinit xf86-input-libinput xorg-fonts-encodings xorg-setxkbmap xorg-xauth xorg-xdpyinfo xorg-xkbcomp xorg-xmessage xorg-xmodmap xorg-xprop xorg-xrandr xorg-xrdb xorg-xset xorg-xsetroot xorg-xwayland xorgproto

	### Set X11 keyboard layout ###
	{
		echo "Section \"InputClass\""
		echo "	Identifier \"system-keyboard\""
		echo "	MatchIsKeyboard \"on\""
		echo "	Option \"XkbLayout\" \"$KEYBOARD_LAYOUT_X11\""
		echo "EndSection"
	} >/mnt/etc/X11/xorg.conf.d/00-keyboard.conf
	echo "XKBLAYOUT=$KEYBOARD_LAYOUT_X11" >>/mnt/etc/vconsole.conf

	### Installing GPU drivers ###
	if [[ "$(cat /sys/class/dmi/id/product_name)" == "VirtualBox" || "$(cat /sys/class/dmi/id/product_name)" == "Standard PC (Q35 + ICH9, 2009)" || "$(cat /sys/class/dmi/id/product_name)" == "VMware Virtual Platform" ]]; then
		echo Running in a VM
		arch-chroot /mnt pacman -S --noconfirm mesa xf86-video-vmware xf86-input-vmware virtualbox-guest-utils
	fi
	if $NVIDIA_USER; then
		if $NVIDIA_PROPRIETARY; then
			printf "\nInstalling nvidia propietary driver...\n"
			arch-chroot /mnt pacman -S --noconfirm "$NVIDIA_PACKAGE" nvidia-settings
			if $MULTILIB_INSTALLATION; then
				arch-chroot /mnt pacman -S --noconfirm lib32-nvidia-utils
			fi
			sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&nvidia-drm.modeset=1 /' /mnt/etc/default/grub
			sed -i 's/MODULES=(/&nvidia nvidia_modeset nvidia_uvm nvidia_drm/' /mnt/etc/mkinitcpio.conf
			arch-chroot /mnt mkinitcpio -P
			arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
			mkdir /mnt/etc/pacman.d/hooks
			{
				echo "[Trigger]"
				echo "Operation=Install"
				echo "Operation=Upgrade"
				echo "Operation=Remove"
				echo "Type=Package"
				echo "Target=$NVIDIA_PACKAGE"
				echo "Target=$KERNEL"
				echo "# Change the linux part above and in the Exec line if a different kernel is used"
				echo
				echo "[Action]"
				echo "Description=Update NVIDIA module in initcpio"
				echo "Depends=mkinitcpio"
				echo "When=PostTransaction"
				echo "NeedsTargets"
				echo "Exec=/bin/sh -c 'while read -r trg; do case trg in $KERNEL) exit 0; esac; done; /usr/bin/mkinitcpio -P'"
			} >/mnt/etc/pacman.d/hooks/nvidia.hook
		else
			echo "Installing nvidia open source driver..."
			arch-chroot /mnt pacman -S --noconfirm mesa xf86-video-nouveau
			if $MULTILIB_INSTALLATION; then
				arch-chroot /mnt pacman -S --noconfirm lib32-mesa
			fi
		fi
	fi
	if $MESA_AMBER; then
		arch-chroot /mnt pacman -S --noconfirm mesa-amber
		if $MULTILIB_INSTALLATION; then
			arch-chroot /mnt pacman -S --noconfirm lib32-mesa-amber
		fi
	else
		arch-chroot /mnt pacman -S --noconfirm mesa
		if $MULTILIB_INSTALLATION; then
			arch-chroot /mnt pacman -S --noconfirm lib32-mesa
		fi
	fi
	if $AMD_USER; then
		arch-chroot /mnt pacman -S --noconfirm xf86-video-amdgpu vulkan-radeon libva-mesa-driver mesa-vdpau
		if $MULTILIB_INSTALLATION; then
			arch-chroot /mnt pacman -S --noconfirm lib32-vulkan-radeon lib32-libva-mesa-driver lib32-mesa-vdpau
		fi
	fi
	if $INTEL_USER; then
		arch-chroot /mnt pacman -S --noconfirm xf86-video-intel vulkan-intel intel-media-driver libva-intel-driver intel-gpu-tools
		if $MULTILIB_INSTALLATION; then
			arch-chroot /mnt pacman -S --noconfirmlib32-vulkan-intel lib32-libva-intel-driver
		fi
	fi
}

desktop_install() {
	case $DESKTOP_TO_INSTALL in
	1)
		printf "Installing Desktop Environment...(KDE Plasma)"
		arch-chroot /mnt pacman -S --noconfirm plasma-meta konsole kate dolphin ark kcalc spectacle sddm sddm-kcm plasma-wayland-session egl-wayland polkit polkit-qt5 polkit-kde-agent partitionmanager packagekit-qt5
		arch-chroot /mnt systemctl enable sddm.service
		;;
	2)
		printf "Installing Desktop Environment...(GNOME)"
		arch-chroot /mnt pacman -S --noconfirm gnome gnome-shell-extensions polkit polkit-gnome p7zip unrar gufw gvfs-goa dconf-editor gnome-shell-extensions gnome-themes-extra gnome-shell-extension-appindicator gnome-firmware
		arch-chroot /mnt systemctl enable gdm.service
		;;
	esac
}

audio_install() {
	printf "Installing Audio packages (pipewire, wireplumer,...)"
	arch-chroot /mnt pacman -S --noconfirm --needed pipewire pipewire-alsa pipewire-jack pipewire-pulse gst-plugin-pipewire libpulse wireplumber
	mkdir -p /mnt/home/"$ARCHUSER"/.config/systemd/user/default.target.wants /mnt/home/"$ARCHUSER"/.config/systemd/user/sockets.target.wants
	chown -hR "$ARCHUSER":"$ARCHUSER" /mnt/home/"$ARCHUSER"/.config/systemd
	ln -s /usr/lib/systemd/user/pipewire-pulse.service /mnt/home/"$ARCHUSER"/.config/systemd/user/default.target.wants/pipewire-pulse.service
	ln -s /usr/lib/systemd/user/pipewire-pulse.socket /mnt/home/"$ARCHUSER"/.config/systemd/user/sockets.target.wants/pipewire-pulse.socket
}

additional_packages() {
	printf "\nInstalling additional_packages...\n"
	arch-chroot /mnt pacman -S --noconfirm --needed nano vim htop wget iwd wireless_tools wpa_supplicant smartmontools xdg-utils neofetch lshw git p7zip unrar unarchiver lzop lrzip libva libva-utils llvm bat realtime-privileges
	$INSTALL_DESKTOP_ENVIRONMENT && arch-chroot /mnt pacman -S --noconfirm --needed firefox
}

post_install() {
	printf "\nPostinstall begins now\n\n"

	usermod -G realtime -a "$ARCHUSER"

	### Fix USB file transfer progress not showing correctly ###
	mkdir /mnt/etc/sysctl.d 2>/dev/null
	touch /mnt/etc/sysctl.d/USB.conf
	echo "vm.dirty_background_bytes = 16777216" >>/mnt/etc/sysctl.d/USB.conf
	echo "vm.dirty_bytes = 50331648" >>/mnt/etc/sysctl.d/USB.conf

	if $INSTALL_OPENSSH; then
		arch-chroot /mnt pacman -S --noconfirm openssh
		arch-chroot /mnt systemctl enable sshd.service
	fi

	if $INSTALL_BLUETOOTH; then
		arch-chroot /mnt pacman -S --noconfirm bluez bluez-utils
		arch-chroot /mnt systemctl enable bluetooth.service
	fi

	if $INSTALL_ANTIVIRUS; then
		arch-chroot /mnt pacman -S --noconfirm clamav
		$INSTALL_DESKTOP_ENVIRONMENT && arch-chroot /mnt pacman -S --noconfirm clamtk
		arch-chroot /mnt systemctl enable --now clamav-freshclam.service
		arch-chroot /mnt systemctl enable --now clamav-daemon.service
	fi

	if $INSTALL_PRINTING; then
		arch-chroot /mnt pacman -S --noconfirm cups
		arch-chroot /mnt systemctl enable --now cups.service
	fi

	if $INSTALL_AUR_HELPER; then
		case $AUR_HELPER in
		1)
			printf "Installing AUR helper...(paru)\n"
			pacman -S --noconfirm --needed git
			arch-chroot /mnt pacman -S --noconfirm --needed git
			mkdir /mnt/home/"$ARCHUSER"/gitclones
			cd /mnt/home/"$ARCHUSER"/gitclones && git clone https://aur.archlinux.org/paru-bin.git && cd paru-bin || exit
			arch-chroot /mnt chown -R "$ARCHUSER":"$ARCHUSER" /home/"$ARCHUSER"/gitclones
			arch-chroot /mnt su "$ARCHUSER" -c "cd /home/$ARCHUSER/gitclones/paru-bin && makepkg"
			PARU_PKG=$(find /mnt/home/"$ARCHUSER"/gitclones/paru-bin/ -name 'paru-bin*.pkg.tar.zst' | cut -c5-)
			arch-chroot /mnt pacman -U --noconfirm "$PARU_PKG"
			cd || exit
			;;
		2)
			printf "Installing AUR helper...(yay)\n"
			pacman -S --noconfirm --needed git
			arch-chroot /mnt pacman -S --noconfirm --needed git
			mkdir /mnt/home/"$ARCHUSER"/gitclones
			cd /mnt/home/"$ARCHUSER"/gitclones && git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin || exit
			arch-chroot /mnt chown -R "$ARCHUSER":"$ARCHUSER" /home/"$ARCHUSER"/gitclones
			arch-chroot /mnt su "$ARCHUSER" -c "cd /home/$ARCHUSER/gitclones/yay-bin && makepkg"
			YAY_PKG=$(find /mnt/home/"$ARCHUSER"/gitclones/yay-bin/ -name 'paru-bin*.pkg.tar.zst' | cut -c5-)
			arch-chroot /mnt pacman -U --noconfirm "$YAY_PKG"
			cd || exit
			;;
		esac
		rm -r /mnt/home/"$ARCHUSER"/gitclones
	fi

	if $INSTALL_CHAOTIC_AUR; then
		arch-chroot /mnt pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
		arch-chroot /mnt pacman-key --lsign-key 3056513887B78AEB
		arch-chroot /mnt pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
		echo "[chaotic-aur]" >>/mnt/etc/pacman.conf
		echo "Include = /etc/pacman.d/chaotic-mirrorlist" >>/mnt/etc/pacman.conf
		arch-chroot /mnt pacman -Syy
	fi

	if $INSTALL_PLYMOUTH; then
		arch-chroot /mnt pacman -S --noconfirm plymouth
		sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&splash /' /mnt/etc/default/grub
		sed -i 's/HOOKS=(base udev /&plymouth /' /mnt/etc/mkinitcpio.conf
		echo "[Daemon]" >/mnt/etc/plymouth/plymouthd.conf
		echo "Theme=bgrt" >>/mnt/etc/plymouth/plymouthd.conf
		arch-chroot /mnt mkinitcpio -P
		arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
	fi

	case $DESKTOP_TO_INSTALL in
	1) ### Set up post install script for KDE Plasma ###
		{
			echo "#!/bin/bash"
			echo
			echo "sleep 10"
			echo "sed -i -n -e '/^gtk-theme-name=Breeze/!p' -e '\$agtk-theme-name=Breeze' /home/$ARCHUSER/.config/gtk-3.0/settings.ini"
			echo "sed -i -n -e '/^gtk-modules=colorreload-gtk-module:window-decorations-gtk-module/!p' -e 'gtk-modules=colorreload-gtk-module:window-decorations-gtk-module' /home/$ARCHUSER/.config/gtk-3.0/settings.ini"
			echo "sed -i -n -e '/^gtk-theme-name=Breeze/!p' -e '\$agtk-theme-name=Breeze' /home/$ARCHUSER/.config/gtk-4.0/settings.ini"
			echo "sed -i -n -e '/^gtk-modules=colorreload-gtk-module:window-decorations-gtk-module/!p' -e 'gtk-modules=colorreload-gtk-module:window-decorations-gtk-module' /home/$ARCHUSER/.config/gtk-4.0/settings.ini"
			echo "plasma-apply-lookandfeel -a org.kde.breezedark.desktop"
		} >/mnt/home/"$ARCHUSER"/Arch_Installer_Post_Install.sh
		mkdir /mnt/etc/sddm.conf.d
		{
			echo "[General]"
			echo "Numlock=on"
			echo
			echo "[Theme]"
			echo "Current=breeze"
		} >/mnt/etc/sddm.conf.d/kde_settings.conf
		if $INSTALL_PLYMOUTH; then
			arch-chroot /mnt pacman -S --noconfirm plymouth-kcm
		fi
		if $INSTALL_FLATPAK; then
			arch-chroot /mnt pacman -S --noconfirm flatpak-kcm
		fi
		;;
	2) ### Set up post install script for GNOME ###
		{
			echo "#!/bin/bash"
			echo
			echo "sleep 10"
			echo "gsettings set org.gnome.desktop.peripherals.touchpad click-method 'fingers'"
			echo "gsettings set org.gnome.shell disable-user-extensions false"
			echo "gsettings set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close'"
		} >/mnt/home/"$ARCHUSER"/Arch_Installer_Post_Install.sh
		;;
	esac

	### Self delete post install script ###
	arch-chroot /mnt pacman -S --noconfirm --needed zenity
	if $INSTALL_DESKTOP_ENVIRONMENT; then
		mkdir -p /mnt/home/"$ARCHUSER"/.config/autostart
		case $DESKTOP_TO_INSTALL in
		1) ### KDE Plasma ###
			{
				echo "[Desktop Entry]"
				echo "Name=Post_Install_Autostarter"
				echo "Exec=konsole -e 'bash -c \"/home/$ARCHUSER/Arch_Installer_Post_Install.sh; bash\"'"
				echo "Type=Application"
			} >/mnt/home/"$ARCHUSER"/.config/autostart/Post_Install_Autostarter.desktop
			;;
		2) ### GNOME ###
			{
				echo "[Desktop Entry]"
				echo "Name=Post_Install_Autostarter"
				echo "Exec=kgx -e 'bash -c \"/home/$ARCHUSER/Arch_Installer_Post_Install.sh; bash\"'"
				echo "Type=Application"
			} >/mnt/home/"$ARCHUSER"/.config/autostart/Post_Install_Autostarter.desktop
			;;
		esac
		{
			echo "rm /home/$ARCHUSER/.config/autostart/Post_Install_Autostarter.desktop"
			printf 'zenity --info --text="Postinstall Complete.\nYou are advised to reboot now."\n'
			echo "rm -- /home/$ARCHUSER/Arch_Installer_Post_Install.sh"
		} >>/mnt/home/"$ARCHUSER"/Arch_Installer_Post_Install.sh
		chmod +x /mnt/home/"$ARCHUSER"/Arch_Installer_Post_Install.sh
	fi

	### Fix permissions on /home/$ARCHUSER ###
	arch-chroot /mnt chown -hR "$ARCHUSER":"$ARCHUSER" /home/"$ARCHUSER"

	printf "\nPostinstall ends now\n"
}

additional_drivers() {
	### Install broadcom-wl package ###
	if lsusb | grep Broadcom >/dev/null || lspci | grep Broadcom >/dev/null; then
		arch-chroot /mnt pacman -S --noconfirm broadcom-wl
	fi

	### Install rtl88xxau-aircrack-dkms-git package ###
	if lsusb | grep RTL8811AU >/dev/null || lsusb | grep RTL8812AU >/dev/null || lsusb | grep RTL8821AU >/dev/null; then
		if $INSTALL_CHAOTIC_AUR; then
			arch-chroot /mnt pacman -S --noconfirm rtl88xxau-aircrack-dkms-git
		elif $INSTALL_AUR_HELPER; then
			case $AUR_HELPER in
			1)
				arch-chroot /mnt su "$ARCHUSER" -c "paru -S --noconfirm rtl88xxau-aircrack-dkms-git"
				;;
			2)
				arch-chroot /mnt su "$ARCHUSER" -c "yay -S --noconfirm rtl88xxau-aircrack-dkms-git"
				;;
			esac
		else
			printf "Realtek RTL88XXAU device detected but no driver is installed! \nYou may not be able to connect to WiFi.\n"
		fi
	fi
}

### The installer itself. Good luck. ###
printf "Arch Linux Install Script by zweiler2 TUI Edition\n"
echo "Start time: $(date)"
pacman -Sy --noconfirm --needed dialog
if [ "$(id -u)" -ne 0 ]; then
	dialog --infobox 'Please run as root!' 3 23
	printf "Please run as root!\n"
	exit 1
fi
check_internet_connection
if dialog --defaultno --title "Arch installer by zweiler2" --yesno 'Do you want to install Arch Linux?\nBy confirming this you also confirm that you read the script and are aware of what it does.\nAlso i am not responsible for any lost data.\nYou have been warned!' 0 0; then
	check_system
	information_gathering
	if ! $MANUAL_PARTITIONING; then
		auto_partitioning
	fi
	base_os_install
	if $INSTALL_DESKTOP_ENVIRONMENT; then
		xorg_graphics_install
		audio_install
		desktop_install
	fi
	additional_packages
	post_install
	additional_drivers
	dialog --title "Arch installer by zweiler2" --msgbox "Installation finished! \nYou may reboot now, or type \"arch-chroot /mnt\" to make further changes" 6 74
	echo "End time: $(date)"
	exit 0
else
	printf "Exiting installer..."
	exit 1
fi

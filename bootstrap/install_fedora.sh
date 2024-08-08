#!/bin/bash
set -e

ErrorExit() {
	echo "Error: $1"
	echo ""
	exit 1
}

LogInfo() {
	printf "\n\e[1m[INFO] %s\e[0m\n" "$1"
}

i() {
	sudo dnf install -y --setopt=install_weak_deps=False --allowerasing --best "$@"
}

mkd() {
	test -d "$1" ||
		mkdir "$1"
}

test -f /etc/fedora-release ||
	ErrorExit "run on fedora based distribution"

command -v dnf ||
	ErrorExit "could not find dnf package utility"

sudo -v ||
	ErrorExit "unable to run sudo commands"

command -v tee ||
    i coreutils

LogInfo "Disable sudo password check"
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/"$USER"

LogInfo "Tune the system with (sysctl)"
sudo tee /etc/sysctl.d/20-"$HOSTNAME".conf <<EOF
vm.swappiness = 10 # be aggressve when swapping out of memory
vm.vfs_cache_pressure = 50 # improve performance on systems with a large number of files
EOF

LogInfo "Update the system"
sudo dnf update -y

LogInfo "Setup DNF repositories"
sudo rpmkeys --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg
sudo tee /etc/yum.repos.d/vscodium.repo <<EOF
[gitlab.com_paulcarroty_vscodium_repo]
name=download.vscodium.com
baseurl=https://download.vscodium.com/rpms/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg
metadata_expire=1h
EOF

# https://docs.fedoraproject.org/en-US/quick-docs/rpmfusion-setup/#_enabling_the_rpm_fusion_repositories_using_command_line_utilities
LogInfo "Install from rpmfusion"
i https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm # rpm fusion free
i https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm   # rpm fusion non-free
sudo dnf -y --allowerasing --best groupupdate multimedia --setop="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
sudo dnf -y groupupdate sound-and-video

LogInfo "Install packages"
i google-roboto-fonts google-roboto-fonts tilix gnome-tweaks vim-enhanced neovim ffmpeg htop ncdu perl-HTML-Parser gnome-extensions-app \
  smartmontools lm_sensors bat gnome-shell-extension-appindicator mplayer libreoffice-draw iotop fio ioping python3-pip blender codium krita vim-default-editor \
  davfs2 fwupd youtube-dl ethtool telnet pwgen p7zip make @virtualization NetworkManager-tui python3-dnf-plugin-versionlock kernel-tools golang-github-prometheus-node-exporter \
  gnome-shell ffmpegthumbnailer file-roller gnome-console gnome-system-monitor gnome-text-editor libavcodec-freeworld nautilus xdg-user-dirs xdg-user-dirs-gtk desktop-backgrounds-gnome \
  gnome-console gnome-software gnome-system-monitor gnome-disk-utility @fonts mesa-dri-drivers mesa-va-drivers

LogInfo "Setup graphics"
case $(lspci|grep ' VGA '| sed -e 's/.*VGA compatible controller://') in
	*Radeon*)
		sudo rm -f /etc/yum.repos.d/rpmfusion-nonfree-nvidia-driver.repo
		i rocm-hip-devel hip-devel radeontop ;;
	*NVIDIA*)
		i akmod-nvidia ;;
	*Virtio*)
		i qemu-device-display-qxl ;;
esac

LogInfo "Boot to GUI"
sudo systemctl set-default graphical.target

if [ -n "$AUTOFS" ]; then
	LogInfo "Setup autofs"
	i autofs
	sudo tee /etc/auto.master <<-EOF
	/n   /etc/autofs/n
	EOF
	mkd /etc/autofs
	sudo tee /etc/autofs/n <<-EOF
	* -rw,intr,hard,nosuid $AUTOFS/&
	EOF
	sudo systemctl enable --now autofs.service
fi

LogInfo "Remove leaf packages"
sudo dnf autoremove -y

LogInfo "Add user to groups"
sudo usermod -aG davfs2 "$USER"

LogInfo "Setup lm-sensors"
sudo sensors-detect --auto

LogInfo "Configure and install flatpaks"
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --noninteractive -y com.makemkv.MakeMKV com.obsproject.Studio com.spotify.Client md.obsidian.Obsidian

if [ "$SYNDRIVE" ]; then
	LogInfo "Setup synology drive"
	flatpak install --noninteractive -y com.spotify.Client com.synology.SynologyDrive
	mkd ~/.config/autostart
	cp /var/lib/flatpak/exports/share/applications/com.synology.SynologyDrive.desktop ~/.config/autostart/
fi

LogInfo "Setup systemd-tmpfiles user service"
mkd ~/.config/user-tmpfiles.d
cat <<EOF > ~/.config/user-tmpfiles.d/custom.conf
d %h/Downloads - - - aAmM:5d -
d %h/tmp - - - aAmM:2w -
d %h/Pictures - - - aAmM:5d -
d %h/KritaRecorder - - - aAmM:5d -
EOF

LogInfo "Setup home directories"
mkd ~/tmp
mkd ~/git
mkd ~/go

systemctl --user restart systemd-tmpfiles-clean.service
systemd-tmpfiles --user --boot --remove --create

LogInfo "Mask tracker services"
systemctl --user mask tracker-extract-3.service tracker-miner-fs-3.service tracker-miner-rss-3.service tracker-writeback-3.service tracker-xdg-portal-3.service tracker-miner-fs-control-3.service


LogInfo "Reboot in 5 minutes"
shutdown -r +5

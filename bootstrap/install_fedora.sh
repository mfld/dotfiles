#!/bin/bash
set -e

ErrorExit() {
	echo "Error: $1"
	echo ""
	exit 1
}

LogInfo() {
	echo ""
	printf "\e[1m[INFO] %s\e[0m" "$1"
}

i() {
	sudo dnf install -y "$@"
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

LogInfo "Install multimedia plugins"
sudo dnf -y group upgrade --with-optional Multimedia

# https://docs.fedoraproject.org/en-US/quick-docs/rpmfusion-setup/#_enabling_the_rpm_fusion_repositories_using_command_line_utilities
LogInfo "Install from rpmfusion"
i https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm # rpm fusion free
i https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm  # rpm fusion non-free
sudo dnf -y --allowerasing --best groupupdate multimedia --setop="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
sudo dnf -y groupupdate sound-and-video

LogInfo "Install packages"
i --allowerasing --best google-roboto-fonts google-roboto-fonts tilix gnome-tweaks vim-enhanced neovim ffmpeg htop ncdu perl-HTML-Parser gnome-extensions-app \
  smartmontools lm_sensors bat gnome-shell-extension-appindicator mplayer libreoffice-draw iotop fio ioping python3-pip blender codium krita vim-default-editor \
  davfs2

LogInfo "Setup graphics"
case $(lspci|grep ' VGA '| sed -e 's/.*VGA compatible controller://') in
	*Radeon*)
		sudo rm -f /etc/yum.repos.d/rpmfusion-nonfree-nvidia-driver.repo
		i rocm-hip-devel hip-devel radeontop ;;
	*NVIDIA*)
		i akmod-nvidia ;;
esac

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
flatpak install -y com.makemkv.MakeMKV com.obsproject.Studio com.spotify.Client md.obsidian.Obsidian

if [ "$SYNDRIVE" ]; then
	LogInfo "Setup synology drive"
	flatpak install -y com.spotify.Client com.synology.SynologyDrive
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

LogInfo "Reboot in 5 minutes"
shutdown -r +5
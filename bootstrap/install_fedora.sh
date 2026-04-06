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
  sudo dnf install -y \
    --allowerasing \
    --setopt=install_weak_deps=False \
    --best \
    --exclude=PackageKit-gstreamer-plugin \
    "$@"
}

NMBridge() {
  IF=$(ip route show default | awk '{print $5}')
  sudo nmcli connection add type bridge ifname br0 stp no
  sudo nmcli connection add type bridge-slave ifname $IF master br0
  sudo nmcli device disconnect $IF
  sudo nmcli connection up bridge-slave-$IF
}

mkd() {
  test -d "$1" ||
    mkdir -p "$1"
}

packages=(
  # Desktop & Browser
  tilix gnome-tweaks gnome-extensions-app gnome-shell-extension-appindicator \
  gnome-software gnome-system-monitor gnome-disk-utility gnome-weather \
  gnome-calculator gnome-characters gnome-pomodoro gnome-text-editor \
  nautilus xdg-user-dirs xdg-user-dirs-gtk desktop-backgrounds-gnome \
  gnome-icon-theme ptyxis file-roller totem loupe evince \
  firefox mozilla-ublock-origin mozilla-privacy-badger mozilla-noscript \
  \
  # Development & Terminal
  vim-enhanced neovim vim-default-editor bat fzf htop ncdu iotop nvtop tree \
  wget tar unzip make git-core golang python3-pip podman podman-docker \
  node-exporter codium p7zip perl-HTML-Parser \
  \
  # Multimedia
  ffmpeg ffmpegthumbnailer mplayer libavcodec-freeworld @multimedia \
  audacity blender krita mesa-dri-drivers mesa-va-drivers mesa-vulkan-drivers libva-utils \
  \
  # System & Networking
  kernel-tools python3-dnf-plugin-versionlock fwupd ethtool net-tools usbutils \
  pciutils smartmontools lm_sensors cifs-utils gvfs-mtp gvfs-smb \
  rsync pwgen telnet bind9-next-utils @virtualization libvirt-daemon NetworkManager-tui \
  ioping fio @fonts plymouth-theme-breeze plymouth-system-theme
)

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
i https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm       # rpm fusion free
i https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm # rpm fusion non-free

LogInfo "Install packages"
i "${packages[@]}"

LogInfo "Add user to groups"
sudo usermod -aG libvirt "$USER"

sudo systemctl enable libvirtd.service node_exporter.service
sudo firewall-cmd --permanent --zone=public --add-port=9100/tcp
sudo firewall-cmd --reload

LogInfo "Configure Firefox preferences"
sudo mkdir -p /etc/firefox/defaults/pref
sudo tee /etc/firefox/defaults/pref/system.js <<-EOF
pref("app.normandy.enabled", false);
EOF

LogInfo "Setup NTSync kernel module"
echo "ntsync" | sudo tee /etc/modules-load.d/ntsync.conf

LogInfo "Setup graphics"
sudo systemctl set-default graphical.target
sudo plymouth-set-default-theme breeze-text -R

case $(lspci | grep ' VGA ' | sed -e 's/.*VGA compatible controller://') in
*Radeon*)
  # https://fedoraproject.org/wiki/SIGs/HC
  sudo usermod -a -G render,video "$USER"
  sudo rm -f /etc/yum.repos.d/rpmfusion-nonfree-nvidia-driver.repo
  i rocm-hip rocm-hip-devel radeontop rocminfo rocm-opencl hiprt

  # https://rpmfusion.org/Howto/Multimedia#Hardware_codecs_with_AMD_.28mesa.29
  sudo dnf swap mesa-va-drivers mesa-va-drivers-freeworld
  sudo dnf swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
  ;;
*NVIDIA*)
  i akmod-nvidia
  ;;
*Virtio*)
  i qemu-device-display-qxl spice-vdagent
  ;;
esac

LogInfo "Setup bridge interface"
ip link show br0 >/dev/null 2>&1 ||
  NMBridge

if [ -n "$AUTOFS" ]; then
  LogInfo "Setup autofs"
  i autofs
  sudo tee /etc/auto.master.d/n.autofs <<-EOF
	/n   /etc/autofs.n --timeout=60
	EOF
  sudo tee /etc/autofs.n <<-EOF
	* -rw,hard,nosuid $AUTOFS/&
	EOF
  sudo systemctl enable --now autofs.service
fi

LogInfo "Remove leaf packages"
sudo dnf autoremove -y

LogInfo "Setup lm-sensors"
systemd-detect-virt -q ||
  sudo sensors-detect --auto

LogInfo "Configure and install flatpaks"
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
sudo flatpak install --noninteractive -y com.makemkv.MakeMKV com.spotify.Client md.obsidian.Obsidian \
  org.signal.Signal com.obsproject.Studio

if [ "$SYNDRIVE" ]; then
  LogInfo "Setup synology drive"
  flatpak install --noninteractive -y com.synology.SynologyDrive
  mkd ~/.config/autostart
  cp /var/lib/flatpak/exports/share/applications/com.synology.SynologyDrive.desktop ~/.config/autostart/
fi

LogInfo "Setup systemd-tmpfiles user service"
mkd ~/.config/user-tmpfiles.d
cat <<EOF >~/.config/user-tmpfiles.d/custom.conf
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

LogInfo "Setup LazyVim"
# https://www.lazyvim.org/installation
[ -d "$HOME/.config/nvim" ] || 
  git clone https://github.com/LazyVim/starter ~/.config/nvim; rm -rf ~/.config/nvim/.git

LogInfo "Reboot in 5 minutes"
sudo shutdown -r +5

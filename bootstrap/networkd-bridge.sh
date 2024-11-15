#!/bin/bash
set -e

sudo dnf install systemd-networkd -y

sudo systemctl disable NetworkManager.service

sudo tee /etc/systemd/network/25-br0.netdev <<-EOF
[NetDev]
Name=br0
Kind=bridge
EOF

sudo systemctl restart systemd-networkd.service

sudo tee /etc/systemd/network/25-br0-en.network <<-EOF
[Match]
Name=en*

[Network]
Bridge=br0
EOF

sudo tee /etc/systemd/network/25-br0.network <<-EOF
[Match]
Name=br0

[Link]
RequiredForOnline=routable

[Network]
DHCP=yes
EOF

sudo rm -f /etc/resolv.conf
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

sudo dnf -y remove NetworkManager

sudo systemctl enable --now systemd-resolved systemd-networkd
sudo systemctl restart systemd-resolved systemd-networkd
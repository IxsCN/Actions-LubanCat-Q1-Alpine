#!/bin/sh
set -eu
cat > /etc/apk/repositories <<'EOF'
https://dl-cdn.alpinelinux.org/alpine/v3.23/main
https://dl-cdn.alpinelinux.org/alpine/v3.23/community
EOF
apk update
apk add --no-cache alpine-base openrc openssh dhcpcd e2fsprogs util-linux kmod htop tio kitty-terminfo tailscale
rc-update add devfs sysinit
rc-update add dmesg sysinit
rc-update add mdev sysinit
rc-update add hwdrivers sysinit
rc-update add cgroups boot
rc-update add networking boot
rc-update add dhcpcd default
rc-update add sshd default
rc-update add crond default
printf '%s\n' 'alpine-q1' > /etc/hostname
printf '%s\n' '127.0.0.1 localhost alpine-q1' > /etc/hosts
printf '%s\n' 'auto lo' 'iface lo inet loopback' > /etc/network/interfaces
# ttyFIQ0 is the Rockchip debug console selected in the vendor device tree.
printf '%s\n' 'ttyFIQ0::respawn:/sbin/getty -L 1500000 ttyFIQ0 vt100' >> /etc/inittab
printf '%s\n' ttyFIQ0 >> /etc/securetty
# Serial console login is available for the first boot; SSH password login is
# disabled until the owner deliberately provisions access.
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
printf '%s\n' 'root:fa' | chpasswd

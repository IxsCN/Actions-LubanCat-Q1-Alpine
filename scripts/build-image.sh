#!/usr/bin/env bash
set -euo pipefail

: "${ALPINE_VERSION:=3.23.4}"
: "${KERNEL_REF:=lbc-develop-6.1}"
: "${UBOOT_REF:=main}"
: "${RKBIN_REF:=main}"

root=$(cd "$(dirname "$0")/.." && pwd)
work="$root/work"
mkdir -p "$work" "$root/dist"
cd "$work"

clone() {
  local repo=$1 ref=$2 dest=$3
  git clone --filter=blob:none --depth 1 --branch "$ref" \
    "https://github.com/LubanCat/$repo.git" "$dest"
  git -C "$dest" rev-parse HEAD
}

clone kernel "$KERNEL_REF" kernel
clone u-boot "$UBOOT_REF" u-boot
clone rkbin "$RKBIN_REF" rkbin

# Build Rockchip's board loader using its matching rkbin repository.
(cd u-boot && ./make.sh rk3528 CROSS_COMPILE=aarch64-linux-gnu-)
loader=$(find u-boot -maxdepth 1 -name '*_loader_*.bin' -print -quit)
test -n "$loader" && test -s "$loader"
test -s u-boot/uboot.img

# Generate the LubanCat Q1 DTB and dae-capable kernel from the same tree.
cd kernel
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
make lubancat_linux_rk3528_defconfig
cp "$root/configs/dae.config" arch/arm64/configs/dae.config
# The kernel's %.config target runs merge_config.sh, which itself invokes make.
make dae.config
make olddefconfig
while IFS= read -r setting; do
  case "$setting" in
    CONFIG_*=y|'# CONFIG_'*' is not set')
      grep -Fxq "$setting" .config || { echo "Missing: $setting" >&2; exit 1; }
      ;;
  esac
done < "$root/configs/dae.config"
make -j"$(nproc)" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
  Image rk3528-lubancat-q1.dtb modules
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
  INSTALL_MOD_PATH="$work/rootfs" modules_install
kernel_release=$(make -s ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- kernelrelease)
test -s arch/arm64/boot/Image
test -s arch/arm64/boot/dts/rockchip/rk3528-lubancat-q1.dtb
aarch64-linux-gnu-readelf -S vmlinux | grep '\.BTF ' > /dev/null
cd "$work"

# Unpack Alpine minirootfs and prepare OpenRC via QEMU user emulation.
mkdir -p rootfs
curl -fL --retry 3 -o alpine.tar.gz \
  "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/aarch64/alpine-minirootfs-${ALPINE_VERSION}-aarch64.tar.gz"
tar --numeric-owner -xzf alpine.tar.gz -C rootfs
install -m 0755 /usr/bin/qemu-aarch64-static rootfs/usr/bin/qemu-aarch64-static
cp "$root/scripts/setup-rootfs.sh" rootfs/tmp/setup-rootfs.sh
cp /etc/resolv.conf rootfs/etc/resolv.conf
mount -t proc proc rootfs/proc
mount --rbind /sys rootfs/sys
mount --rbind /dev rootfs/dev
cleanup() {
  umount -R rootfs/dev 2>/dev/null || true
  umount -R rootfs/sys 2>/dev/null || true
  umount rootfs/proc 2>/dev/null || true
}
trap cleanup EXIT
chroot rootfs /bin/sh /tmp/setup-rootfs.sh
cleanup
trap - EXIT
rm -f rootfs/usr/bin/qemu-aarch64-static rootfs/tmp/setup-rootfs.sh rootfs/etc/resolv.conf
# Vendor kernel modules match the generated Image, rather than Alpine's APK kernels.
find rootfs/lib/modules -type l -delete
# Keep Alpine module dependency metadata in sync with the vendor kernel.
depmod -b rootfs "$kernel_release"

# Populate the Q1 extboot partition with the vendor U-Boot boot script.
mkdir -p boot/uEnv
cp kernel/arch/arm64/boot/Image boot/Image
cp kernel/arch/arm64/boot/dts/rockchip/rk3528-lubancat-q1.dtb boot/rk-kernel.dtb
curl -fLsS "https://raw.githubusercontent.com/LubanCat/kernel/${KERNEL_REF}/arch/arm64/boot/dts/rockchip/uEnv/boot.cmd" \
  -o boot/boot.cmd
cp kernel/arch/arm64/boot/dts/rockchip/uEnv/rk3528/uEnvLubanCatQ1.txt boot/uEnv/uEnv.txt
# No distribution initrd: boot.cmd will call booti with '-'.
sed -i '/^initrd=/d' boot/uEnv/uEnv.txt
# Prefer the rootfs PARTUUID provided by the vendor parameter file; it is
# stable even if the SD card is enumerated as a different mmcblk device.
sed -i 's/root=\/dev\/mmcblk${devnum}p${rootfs_part}/root=PARTUUID=614e0000-0000-4b53-8000-1d28000054a9/' boot/boot.cmd
# The vendor DTB has an older abbreviated PARTUUID bootarg: the script above
# overrides it after loading the DTB.
mkimage -A arm -T script -C none -d boot/boot.cmd boot/boot.scr
# Check the boot script still looks up the GPT rootfs partition by name.
grep -Fq 'part number ${devtype} ${devnum} "rootfs"' boot/boot.cmd

# Vendor extboot partition: 0x8000 sectors start, 0x40000 sectors = 128 MiB.
truncate -s 128M boot.img
mkfs.ext2 -F -L boot -d boot boot.img
# Match parameter-extboot.txt: uboot@0x4000, boot@0x8000, rootfs@0x48000.
root_mb=$(( ($(du -sm rootfs | cut -f1) + 256 + 63) / 64 * 64 ))
truncate -s "${root_mb}M" rootfs.img
mkfs.ext4 -F -L rootfs -U 614e0000-0000-4b53-8000-1d28000054a9 \
  -d rootfs rootfs.img

python3 "$root/scripts/pack-sd.py" \
  --loader "$loader" --uboot u-boot/uboot.img \
  --boot boot.img --rootfs rootfs.img \
  --output "$root/dist/lubancat-q1-sd-alpine-${ALPINE_VERSION}.img"
gzip -1 "$root/dist/lubancat-q1-sd-alpine-${ALPINE_VERSION}.img"
printf 'Kernel: %s\n' "$kernel_release"

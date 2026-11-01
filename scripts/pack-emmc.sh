#!/usr/bin/env bash
# Build a Rockchip USB flashing update.img from the same components as the SD image.
set -euo pipefail

: "${ALPINE_VERSION:=3.23.4}"
root=$(cd "$(dirname "$0")/.." && pwd)
work="$root/work"
out="$root/dist/lubancat-q1-emmc-alpine-${ALPINE_VERSION}.update.img"

# Use the vendor's package description and Linux packing tools from fixed
# revisions. The package layout must agree with parameter-extboot.txt and the
# SD image partition locations.
device_commit=1f1392c6e7f43d4654b24d2fcfefed5811e61a7a
tools_commit=210be81d659a6bc4e7a648744ae77837f394be0f
pack_dir="$work/emmc-package"
tools_dir="$work/pack-tools"
mkdir -p "$pack_dir" "$tools_dir" "$root/dist"
# Refuse partial reruns that could accidentally mix outputs from two builds.
if [ -e "$pack_dir/package-file" ] || [ -e "$out" ]; then
  echo "Existing eMMC packaging output found; use a fresh workspace" >&2
  exit 1
fi

fetch() {
  curl --fail --location --silent --show-error --retry 3 \
    --connect-timeout 15 --max-time 180 "$1" -o "$2"
  test -s "$2"
}
base="https://raw.githubusercontent.com/LubanCat/device_rockchip/$device_commit/.chips/rk3528"
fetch "$base/parameter-extboot.txt" "$pack_dir/parameter.txt"
fetch "$base/package-file-extboot" "$pack_dir/package-file"
base="https://raw.githubusercontent.com/LubanCat/tools/$tools_commit/linux/Linux_Pack_Firmware/rockdev"
fetch "$base/afptool" "$tools_dir/afptool"
fetch "$base/rkImageMaker" "$tools_dir/rkImageMaker"
chmod 755 "$tools_dir/afptool" "$tools_dir/rkImageMaker"

# The SDK calls the packed loader MiniLoaderAll.bin. The eMMC package shares
# the same U-Boot build and boot/rootfs filesystem images as the SD image.
loader=$(find "$work/u-boot" -maxdepth 1 -name '*_loader_*.bin' -print -quit)
test -n "$loader" && test -s "$loader"
cp "$loader" "$pack_dir/MiniLoaderAll.bin"
for image in uboot boot rootfs; do
  if [ "$image" = uboot ]; then
    source_image="$work/u-boot/uboot.img"
  else
    source_image="$work/$image.img"
  fi
  test -s "$source_image" || { echo "Missing $source_image" >&2; exit 1; }
  cp --reflink=auto "$source_image" "$pack_dir/$image.img"
done

# Fail if the published vendor format changes unexpectedly.
grep -Fxq 'TYPE: GPT' "$pack_dir/parameter.txt"
grep -Fqx 'uuid:rootfs=614e0000-0000-4b53-8000-1d28000054a9' "$pack_dir/parameter.txt"
grep -Fqx 'CMDLINE: mtdparts=:0x00004000@0x00004000(uboot),0x00040000@0x00008000(boot:bootable),-@0x00048000(rootfs:grow)' "$pack_dir/parameter.txt"
python3 - "$pack_dir/package-file" <<'PY'
import pathlib, sys
rows = [line.split() for line in pathlib.Path(sys.argv[1]).read_text().splitlines()
        if line.strip() and not line.startswith('#')]
expected = [('package-file', 'package-file'), ('parameter', 'parameter.txt'),
            ('bootloader', 'MiniLoaderAll.bin'), ('uboot', 'uboot.img'),
            ('boot', 'boot.img'), ('rootfs', 'rootfs.img')]
if [tuple(row) for row in rows] != expected:
    raise SystemExit(f'Unexpected vendor package-file: {rows}')
PY

# Match LubanCat/device_rockchip/common/scripts/mk-updateimg.sh: its TAG
# comes from four bytes at offset 21 of the generated MiniLoaderAll.bin.
tag=$(python3 - "$pack_dir/MiniLoaderAll.bin" <<'PY'
import pathlib, sys
with pathlib.Path(sys.argv[1]).open('rb') as f:
    f.seek(21)
    raw = f.read(4)
if len(raw) != 4 or any(c not in b'0123456789' for c in raw):
    raise SystemExit(f'Unexpected RK loader chip bytes: {raw!r}')
print('RK' + raw[::-1].decode('ascii'))
PY
)
if [ "$tag" != RK3528 ]; then
  echo "Loader chip tag is $tag, expected RK3528" >&2
  exit 1
fi

(cd "$pack_dir" && "$tools_dir/afptool" -pack ./ "$work/update.raw.img")
test -s "$work/update.raw.img"
"$tools_dir/rkImageMaker" -"$tag" "$pack_dir/MiniLoaderAll.bin" \
  "$work/update.raw.img" "$out" -os_type:androidos
test -s "$out"
file "$out"
sha256sum "$out" > "$out.sha256"
echo "Rockchip USB flashing image: $out"

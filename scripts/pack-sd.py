#!/usr/bin/env python3
"""Pack the LubanCat RK3528 extboot GPT layout into an SD image."""
import argparse
import os
import struct
import uuid
import zlib
from pathlib import Path

SECTOR = 512
ALIGN = 2048  # 1 MiB, aligned with the vendor partition locations
UBOOT = 0x4000
BOOT = 0x8000
ROOT = 0x48000
BOOT_END = ROOT
ROOT_GUID = uuid.UUID('614e0000-0000-4b53-8000-1d28000054a9')

def guid(value):
    return value.bytes_le

def crc(data):
    return zlib.crc32(data) & 0xffffffff

def roundup(value, multiple):
    return (value + multiple - 1) // multiple * multiple

def write_at(out, path, sector, capacity=None):
    size = os.path.getsize(path)
    if capacity is not None and size > capacity * SECTOR:
        raise ValueError(f'{path}: {size} exceeds {capacity * SECTOR} bytes')
    out.seek(sector * SECTOR)
    with open(path, 'rb') as src:
        while block := src.read(4 * 1024 * 1024):
            out.write(block)

def pack(args):
    loader_sectors = roundup(os.path.getsize(args.loader), SECTOR) // SECTOR
    if loader_sectors > UBOOT - 64:
        raise ValueError('loader overlaps the GPT or uboot partition')
    root_sectors = roundup(os.path.getsize(args.rootfs), SECTOR) // SECTOR
    if root_sectors <= 0 or root_sectors > 0xffffffff:
        raise ValueError('invalid rootfs size')
    total_sectors = roundup(ROOT + root_sectors + ALIGN, ALIGN)
    last_usable = total_sectors - 34
    root_end = ROOT + root_sectors - 1
    if root_end > last_usable:
        raise ValueError('rootfs overlaps backup GPT')
    entries = bytearray(128 * 128)
    def entry(index, first, last, part_guid, name, attributes=0):
        # Linux filesystem partition type; boot also uses Linux filesystem type.
        data = struct.pack('<16s16sQQQ72s',
            guid(uuid.UUID('0fc63daf-8483-4772-8e79-3d69d8477de4')),
            guid(part_guid), first, last, attributes, name.encode('utf-16le').ljust(72, b'\x00'))
        entries[index * 128:(index + 1) * 128] = data
    entry(0, UBOOT, BOOT - 1, uuid.uuid4(), 'uboot')
    entry(1, BOOT, BOOT_END - 1, uuid.uuid4(), 'boot', 1 << 2)
    entry(2, ROOT, root_end, ROOT_GUID, 'rootfs')
    disk_guid = uuid.uuid4()
    entries_crc = crc(entries)
    def header(current, backup, entry_sector):
        data = bytearray(512)
        struct.pack_into('<8sIIIIQQQQ16sQIII', data, 0,
            b'EFI PART', 0x00010000, 92, 0, 0, current, backup,
            34, last_usable, guid(disk_guid), entry_sector, 128, 128,
            entries_crc)
        struct.pack_into('<I', data, 16, crc(data[:92]))
        return data
    with open(args.output, 'wb') as out:
        out.truncate(total_sectors * SECTOR)
        mbr = bytearray(512)
        mbr[446 + 4] = 0xee
        struct.pack_into('<II', mbr, 446 + 8, 1, min(total_sectors - 1, 0xffffffff))
        mbr[510:512] = b'\x55\xaa'
        out.seek(0); out.write(mbr)
        out.seek(SECTOR); out.write(header(1, total_sectors - 1, 2))
        out.seek(2 * SECTOR); out.write(entries)
        out.seek((total_sectors - 33) * SECTOR); out.write(entries)
        out.seek((total_sectors - 1) * SECTOR)
        out.write(header(total_sectors - 1, 1, total_sectors - 33))
        # Rockchip BootROM locates the vendor loader at LBA 64.
        write_at(out, args.loader, 64, UBOOT - 64)
        write_at(out, args.uboot, UBOOT, BOOT - UBOOT)
        write_at(out, args.boot, BOOT, BOOT_END - BOOT)
        write_at(out, args.rootfs, ROOT, root_sectors)
    print(f'Image: {args.output} ({total_sectors * SECTOR} bytes), rootfs PARTUUID={ROOT_GUID}')

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    for key in ('loader', 'uboot', 'boot', 'rootfs', 'output'):
        p.add_argument('--' + key, type=Path, required=True)
    pack(p.parse_args())

#!/usr/bin/env python3
"""Inspect an .ipa and fail loudly if it would not install.

Usage:
    python tools/inspect_ipa.py build/LightWord-unsigned.ipa

Checks the zip layout, Info.plist keys, the Mach-O architecture and the minimum
iOS version. Runs in CI and can be run on Windows, so a broken artifact is
caught before it ever reaches a phone.
"""
from __future__ import annotations

import plistlib
import struct
import sys
import zipfile
from pathlib import Path

MAX_IPA_MB = 30.0

MACHO_MAGIC_64 = 0xFEEDFACF
MACHO_MAGIC_32 = 0xFEEDFACE
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_LE = 0xBEBAFECA

LC_BUILD_VERSION = 0x32
LC_VERSION_MIN_IPHONEOS = 0x25

CPU_ARCH_ABI64 = 0x01000000
CPU_TYPE_ARM = 12
CPU_TYPE_ARM64 = CPU_TYPE_ARM | CPU_ARCH_ABI64
CPU_TYPE_X86_64 = 7 | CPU_ARCH_ABI64

PLATFORM_IOS = 2
PLATFORM_IOSSIMULATOR = 7

CPU_NAMES = {
    CPU_TYPE_ARM64: "arm64",
    CPU_TYPE_ARM: "armv7",
    CPU_TYPE_X86_64: "x86_64",
}


class Problem(Exception):
    pass


def decode_version(value: int) -> str:
    return f"{value >> 16}.{(value >> 8) & 0xFF}.{value & 0xFF}"


def describe_macho(data: bytes) -> tuple[str, str | None, str | None]:
    """Returns (arch, min_os, platform) for a thin or fat Mach-O."""
    if len(data) < 32:
        raise Problem("executable too small to be Mach-O")

    magic = struct.unpack(">I", data[:4])[0]

    if magic in (FAT_MAGIC, FAT_MAGIC_LE):
        order = ">" if magic == FAT_MAGIC else "<"
        count = struct.unpack(order + "I", data[4:8])[0]
        if count < 1:
            raise Problem("fat binary without architectures")
        # First arch slice
        offset = struct.unpack(order + "I", data[16:20])[0]
        return describe_macho(data[offset:])

    order = "<"
    if struct.unpack("<I", data[:4])[0] == MACHO_MAGIC_64:
        header = "<"
        is_64 = True
    elif struct.unpack("<I", data[:4])[0] == MACHO_MAGIC_32:
        header = "<"
        is_64 = False
    elif magic in (MACHO_MAGIC_64, MACHO_MAGIC_32):
        header = ">"
        is_64 = magic == MACHO_MAGIC_64
    else:
        raise Problem(f"unknown Mach-O magic 0x{magic:08x}")

    cputype = struct.unpack(header + "i", data[4:8])[0]
    ncmds = struct.unpack(header + "I", data[16:20])[0]
    arch = CPU_NAMES.get(cputype, f"cpu{cputype}")
    if is_64 and cputype == CPU_TYPE_ARM64:
        arch = "arm64"

    offset = 32 if is_64 else 28
    min_os: str | None = None
    platform: str | None = None

    for _ in range(ncmds):
        if offset + 8 > len(data):
            break
        cmd, cmdsize = struct.unpack(header + "II", data[offset : offset + 8])
        if cmdsize == 0:
            break
        if cmd == LC_BUILD_VERSION and offset + 24 <= len(data):
            _, _, plat, minos, _sdk, _ntools = struct.unpack(
                header + "IIIIII", data[offset : offset + 24]
            )
            min_os = decode_version(minos)
            platform = "iOS" if plat == PLATFORM_IOS else (
                "iOS-simulator" if plat == PLATFORM_IOSSIMULATOR else f"platform{plat}"
            )
        elif cmd == LC_VERSION_MIN_IPHONEOS and offset + 16 <= len(data):
            _, _, version, _sdk = struct.unpack(header + "IIII", data[offset : offset + 16])
            min_os = decode_version(version)
            platform = "iOS"
        offset += cmdsize

    return arch, min_os, platform


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: python tools/inspect_ipa.py <path/to/app.ipa>", file=sys.stderr)
        return 2

    ipa = Path(argv[1])
    if not ipa.exists():
        print(f"FAIL missing ipa: {ipa}", file=sys.stderr)
        return 1

    size_mb = ipa.stat().st_size / (1024 * 1024)
    print(f"IPA   {ipa}  ({size_mb:.2f} MB)")

    problems: list[str] = []

    if size_mb > MAX_IPA_MB:
        problems.append(f"ipa is {size_mb:.1f} MB, above the {MAX_IPA_MB:.0f} MB budget")

    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()
        apps = sorted({name.split("/")[1] for name in names if name.startswith("Payload/") and name.count("/") >= 2})
        if len(apps) != 1:
            problems.append(f"expected exactly one .app in Payload/, found {apps}")
            print("\n".join(problems))
            return 1

        app = apps[0]
        if not app.endswith(".app"):
            problems.append(f"Payload/{app} does not end with .app")
        root = f"Payload/{app}"

        info_name = f"{root}/Info.plist"
        if info_name not in names:
            problems.append("missing Info.plist inside .app")
            print("\n".join(problems))
            return 1

        info = plistlib.loads(archive.read(info_name))

        for key in (
            "CFBundleIdentifier",
            "CFBundleExecutable",
            "CFBundleShortVersionString",
            "CFBundleVersion",
            "MinimumOSVersion",
        ):
            value = info.get(key)
            if not value:
                problems.append(f"Info.plist missing {key}")
            else:
                print(f"  {key:26} {value}")

        executable = info.get("CFBundleExecutable") or ""
        executable_name = f"{root}/{executable}"
        if executable_name not in names:
            problems.append(f"missing executable {executable}")
            arch = min_os = platform = None
        else:
            data = archive.read(executable_name)
            try:
                arch, min_os, platform = describe_macho(data)
                print(f"  {'executable':26} {executable} ({len(data) / 1024:.0f} KB)")
                print(f"  {'arch / min OS':26} {arch} / iOS {min_os or '?'} ({platform or '?'})")
            except Problem as error:
                problems.append(str(error))
                arch = min_os = platform = None

        if arch and arch != "arm64":
            problems.append(f"device build must be arm64, got {arch}")
        if platform and platform != "iOS":
            problems.append(f"built for {platform}, not for a device")
        if min_os:
            major = int(min_os.split(".")[0])
            if major > 16:
                problems.append(f"MinimumOSVersion {min_os} is higher than the project target 16.0")

        resources = [n for n in names if n.startswith(root + "/") and not n.endswith("/")]
        print(f"  {'bundle files':26} {len(resources)}")

        if f"{root}/Assets.car" not in names:
            problems.append("Assets.car missing — app icon will not render")
        if f"{root}/PrivacyInfo.xcprivacy" not in names:
            problems.append("PrivacyInfo.xcprivacy missing")
        if not any(n.startswith(f"{root}/Wordbooks/") for n in names):
            problems.append("no word book shipped in Wordbooks/")

        for name in names:
            if "__MACOSX" in name or name.endswith(".DS_Store"):
                problems.append(f"junk entry in archive: {name}")
                break

    if problems:
        print("")
        for problem in problems:
            print(f"FAIL {problem}", file=sys.stderr)
        return 1

    print("\nOK    artifact looks installable")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

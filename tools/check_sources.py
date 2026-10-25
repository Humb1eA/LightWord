#!/usr/bin/env python3
"""Static checks that run on any OS (no Swift toolchain needed).

    python tools/check_sources.py

Catches the class of mistakes a unit test cannot: unbalanced braces, a stray
UIKit/SwiftUI import in the platform-agnostic core, a resource referenced by the
build script but missing on disk, malformed Info.plist / asset catalog JSON.
"""
from __future__ import annotations

import json
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
CORE = SOURCES / "WordCore"
APP = SOURCES / "LightWord"

APPLE_ONLY = ("UIKit", "SwiftUI", "AVFoundation", "UserNotifications", "Combine", "Charts")

problems: list[str] = []


def fail(message: str) -> None:
    problems.append(message)


def strip_noise(text: str) -> str:
    """Remove comments and string literals so brackets can be counted sanely."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r'"""(?:.|\n)*?"""', '""', text)
    text = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', text)
    return text


def check_braces(path: Path) -> None:
    text = strip_noise(path.read_text(encoding="utf-8"))
    for opening, closing in (("{", "}"), ("(", ")"), ("[", "]")):
        depth = 0
        for char in text:
            if char == opening:
                depth += 1
            elif char == closing:
                depth -= 1
            if depth < 0:
                fail(f"{path.relative_to(ROOT)}: unbalanced '{closing}'")
                return
        if depth != 0:
            fail(f"{path.relative_to(ROOT)}: {depth} unclosed '{opening}'")


def check_core_is_platform_agnostic() -> None:
    for path in sorted(CORE.glob("*.swift")):
        for line in path.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if not stripped.startswith("import "):
                continue
            module = stripped.split()[1]
            if module != "Foundation":
                fail(f"{path.relative_to(ROOT)}: WordCore must only import Foundation, found {module}")
    for path in list(CORE.glob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for token in APPLE_ONLY:
            if re.search(r"\b" + token + r"\b", strip_noise(text)):
                fail(f"{path.relative_to(ROOT)}: uses {token}, which is not testable off-device")


def check_swift_files_present() -> None:
    core_files = sorted(CORE.glob("*.swift"))
    app_files = sorted(APP.rglob("*.swift"))
    if len(core_files) < 8:
        fail(f"expected at least 8 core sources, found {len(core_files)}")
    if len(app_files) < 8:
        fail(f"expected at least 8 app sources, found {len(app_files)}")

    declared = set()
    for path in core_files + list(app_files):
        for match in re.finditer(r"\b(?:struct|class|enum)\s+([A-Z]\w+)", path.read_text(encoding="utf-8")):
            declared.add(match.group(1))

    for required in ("DayKey", "Word", "Scheduler", "SessionBuilder", "LearningState", "AppStore"):
        if required not in declared:
            fail(f"type {required} is not declared anywhere")


def check_package() -> None:
    package = (ROOT / "Package.swift").read_text(encoding="utf-8")
    for path in ("Sources/WordCore", "Tests/CoreTests"):
        if path not in package:
            fail(f"Package.swift does not reference {path}")
        if not (ROOT / path).exists():
            fail(f"Package.swift path does not exist: {path}")


def check_resources() -> None:
    info_path = ROOT / "Resources" / "Info.plist"
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    for key in (
        "CFBundleIdentifier",
        "CFBundleExecutable",
        "CFBundleShortVersionString",
        "CFBundleVersion",
        "MinimumOSVersion" if "MinimumOSVersion" in info else "UILaunchScreen",
        "UISupportedInterfaceOrientations",
        "UIRequiredDeviceCapabilities",
    ):
        if key not in info:
            fail(f"Info.plist missing {key}")
    if info.get("UIRequiredDeviceCapabilities") != ["arm64"]:
        fail("UIRequiredDeviceCapabilities should be ['arm64']")
    if info.get("CFBundleExecutable") not in ("$(EXECUTABLE_NAME)", "LightWord"):
        fail("CFBundleExecutable must be substituted by the build script")

    privacy = json.loads((ROOT / "Resources" / "PrivacyInfo.xcprivacy").read_text(encoding="utf-8"))
    if privacy.get("NSPrivacyTracking") is not False:
        fail("PrivacyInfo.xcprivacy should declare NSPrivacyTracking = false")

    assets = ROOT / "Resources" / "Assets.xcassets"
    for contents in sorted(assets.rglob("Contents.json")):
        json.loads(contents.read_text(encoding="utf-8"))
    icon_set = assets / "AppIcon.appiconset"
    for entry in json.loads((icon_set / "Contents.json").read_text(encoding="utf-8"))["images"]:
        filename = entry.get("filename")
        if filename and not (icon_set / filename).exists():
            fail(f"app icon {filename} referenced by Contents.json but missing")
    icon_png = icon_set / "AppIcon.png"
    if not icon_png.exists():
        fail("AppIcon.png missing — run python tools/make_icon.py")

    books = list((ROOT / "Resources" / "Wordbooks").glob("*.json"))
    if not books:
        fail("no word book in Resources/Wordbooks")
    for book in books:
        payload = json.loads(book.read_text(encoding="utf-8"))
        if len(payload.get("words", [])) < 1000:
            fail(f"{book.name}: suspiciously few words ({len(payload.get('words', []))})")


def check_build_script() -> None:
    script = (ROOT / "tools" / "build-ipa.sh").read_text(encoding="utf-8")
    for needle in ("swiftc", "actool", "PlistBuddy", "Payload", "PrivacyInfo.xcprivacy", "Wordbooks"):
        if needle not in script:
            fail(f"build-ipa.sh does not mention {needle}")


def main() -> int:
    swift_files = sorted(list(CORE.glob("*.swift")) + list(APP.rglob("*.swift")))
    if not swift_files:
        fail("no Swift sources found")

    for path in swift_files:
        check_braces(path)

    check_core_is_platform_agnostic()
    check_swift_files_present()
    check_package()
    check_resources()
    check_build_script()

    total_lines = sum(len(p.read_text(encoding="utf-8").splitlines()) for p in swift_files)
    print(f"swift files:  {len(swift_files)}")
    print(f"swift lines:  {total_lines}")

    if problems:
        print("")
        for problem in problems:
            print(f"FAIL {problem}")
        return 1

    print("OK   static checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

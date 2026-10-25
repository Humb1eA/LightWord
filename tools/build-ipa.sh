#!/usr/bin/env bash
# Build an *unsigned* IPA for sideloading (Sideloadly / AltStore / ESign).
#
# Runs on macOS with Xcode Command Line Tools (no .xcodeproj needed), locally or
# in GitHub Actions. The output is intentionally not code-signed: the signing
# tool on your PC injects your own certificate and provisioning profile.
#
#   bash tools/build-ipa.sh
#   BUNDLE_ID=com.yourname.lightword bash tools/build-ipa.sh
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="LightWord"
BUNDLE_ID="${BUNDLE_ID:-com.local.lightword}"
MIN_IOS="16.0"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
IPA_PATH="$BUILD_DIR/$APP_NAME-unsigned.ipa"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "error: xcrun not found — this script must run on macOS with Xcode CLT installed" >&2
  exit 1
fi

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "==> SDK: $SDK"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR"

echo "==> compiling Swift (arm64, min iOS $MIN_IOS)"
# shellcheck disable=SC2046
xcrun -sdk iphoneos swiftc \
  -sdk "$SDK" \
  -target "arm64-apple-ios${MIN_IOS}" \
  -module-name "$APP_NAME" \
  -parse-as-library \
  -swift-version 5 \
  -O -whole-module-optimization \
  -Xlinker -dead_strip \
  -o "$APP_DIR/$APP_NAME" \
  $(find Sources/WordCore Sources/LightWord -name '*.swift' | sort)

echo "==> compiling asset catalog"
xcrun -sdk iphoneos actool Resources/Assets.xcassets \
  --compile "$APP_DIR" \
  --platform iphoneos \
  --minimum-deployment-target "$MIN_IOS" \
  --target-device iphone \
  --app-icon AppIcon \
  --output-partial-info-plist "$BUILD_DIR/assets.plist" \
  --output-format human-readable-text

echo "==> assembling bundle"
cp Resources/Info.plist "$APP_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Merge $BUILD_DIR/assets.plist" "$APP_DIR/Info.plist"
printf 'APPL????' > "$APP_DIR/PkgInfo"
cp Resources/PrivacyInfo.xcprivacy "$APP_DIR/PrivacyInfo.xcprivacy"
mkdir -p "$APP_DIR/Wordbooks"
cp Resources/Wordbooks/*.json "$APP_DIR/Wordbooks/"

xattr -cr "$APP_DIR" 2>/dev/null || true

echo "==> packaging payload"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_DIR" "$BUILD_DIR/Payload/"
( cd "$BUILD_DIR" && zip -qry "$(basename "$IPA_PATH")" Payload )
rm -rf "$BUILD_DIR/Payload"

echo "==> done"
ls -lh "$IPA_PATH"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
APP="$DIST_DIR/Yagraker.app"
UNIVERSAL_SCRATCH="$ROOT/.build/yagraker-universal"
SIGN_IDENTITY="${SIGN_IDENTITY:-Yagraker Local Development}"
FEED_URL="${YAGRAKER_FEED_URL:-}"
PUBLIC_ED_KEY="${YAGRAKER_PUBLIC_ED_KEY:-}"
NOTARY_PROFILE="${NOTARYTOOL_PROFILE:-}"
FINAL_ARCHIVE="$DIST_DIR/Yagraker.zip"

if [[ -n "$FEED_URL" || -n "$PUBLIC_ED_KEY" ]]; then
    if [[ -z "$FEED_URL" || -z "$PUBLIC_ED_KEY" ]]; then
        echo "YAGRAKER_FEED_URL and YAGRAKER_PUBLIC_ED_KEY must be supplied together" >&2
        exit 1
    fi
    if [[ "$FEED_URL" != https://* ]]; then
        echo "YAGRAKER_FEED_URL must use HTTPS" >&2
        exit 1
    fi
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "Ad-hoc signing is unsupported because it invalidates Accessibility permission after every rebuild" >&2
    exit 1
fi

IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning -s "$SIGN_IDENTITY")"
if [[ "$IDENTITIES" == *"0 valid identities found"* ]]; then
    echo "Code-signing identity not found: $SIGN_IDENTITY" >&2
    echo "Create 'Yagraker Local Development' in Keychain Access or set SIGN_IDENTITY to a stable identity" >&2
    exit 1
fi

if [[ -n "$NOTARY_PROFILE" && ( -z "$FEED_URL" || -z "$PUBLIC_ED_KEY" ) ]]; then
    echo "Notarized builds require YAGRAKER_FEED_URL and YAGRAKER_PUBLIC_ED_KEY" >&2
    exit 1
fi

echo "==> Building universal arm64 + x86_64"
# Build both slices in one SwiftPM graph. This is important for dependencies
# using compiler macros: host plugins are built once for the host architecture,
# while runtime targets receive both requested slices.
swift build \
    --package-path "$ROOT" \
    --configuration "$CONFIGURATION" \
    --arch arm64 \
    --arch x86_64 \
    --scratch-path "$UNIVERSAL_SCRATCH"

BIN_DIR="$(swift build \
    --package-path "$ROOT" \
    --configuration "$CONFIGURATION" \
    --arch arm64 \
    --arch x86_64 \
    --scratch-path "$UNIVERSAL_SCRATCH" \
    --show-bin-path)"

rm -rf "$APP" "$FINAL_ARCHIVE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"

if [[ -n "$FEED_URL" ]]; then
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $FEED_URL" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $PUBLIC_ED_KEY" "$APP/Contents/Info.plist"
fi

/bin/cp "$BIN_DIR/Yagraker" "$APP/Contents/MacOS/Yagraker"
/usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Yagraker"

# Every statically linked SPM target with Bundle.module needs its companion bundle.
while IFS= read -r -d '' bundle; do
    /bin/cp -R "$bundle" "$APP/Contents/Resources/"
done < <(/usr/bin/find "$BIN_DIR" -maxdepth 1 -type d -name '*.bundle' -print0)

# Info.plist permission prompts must live in the app's main localization folders.
for localization in "$ROOT"/Support/*.lproj; do
    [[ -d "$localization" ]] || continue
    language="${localization##*/}"
    mkdir -p "$APP/Contents/Resources/$language"
    /bin/cp "$localization/InfoPlist.strings" "$APP/Contents/Resources/$language/InfoPlist.strings"
    /usr/bin/plutil -lint "$APP/Contents/Resources/$language/InfoPlist.strings"
done

SPARKLE_FRAMEWORK="$UNIVERSAL_SCRATCH/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    SPARKLE_FRAMEWORK="$(/usr/bin/find "$ROOT/.build" -type d -name Sparkle.framework -print -quit)"
fi
if [[ -z "$SPARKLE_FRAMEWORK" || ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "Sparkle.framework not found after build" >&2
    exit 1
fi
/bin/cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"

/usr/bin/xcrun swift \
    "$ROOT/Scripts/generate-icon.swift" \
    "$ROOT/Sources/Yagraker/Resources/yagraker-mark.svg" \
    "$APP/Contents/Resources/AppIcon.icns"
/bin/chmod +x "$APP/Contents/MacOS/Yagraker"

if [[ -n "$NOTARY_PROFILE" ]]; then
    /usr/bin/codesign --force --deep --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" \
        "$APP"
else
    /usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" \
        "$APP"
fi

/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE_INFO="$(/usr/bin/codesign -dvv "$APP" 2>&1)"
if [[ "$SIGNATURE_INFO" == *"Signature=adhoc"* ]]; then
    echo "Built app unexpectedly has an ad-hoc signature" >&2
    exit 1
fi
/usr/bin/lipo -info "$APP/Contents/MacOS/Yagraker"
/usr/bin/lipo -verify_arch arm64 "$APP/Contents/MacOS/Yagraker"
/usr/bin/lipo -verify_arch x86_64 "$APP/Contents/MacOS/Yagraker"
/usr/bin/lipo -info "$APP/Contents/Frameworks/Sparkle.framework/Sparkle"
/usr/bin/lipo -verify_arch arm64 "$APP/Contents/Frameworks/Sparkle.framework/Sparkle"
/usr/bin/lipo -verify_arch x86_64 "$APP/Contents/Frameworks/Sparkle.framework/Sparkle"

if [[ -n "$NOTARY_PROFILE" ]]; then
    NOTARY_ARCHIVE="$DIST_DIR/Yagraker-notarization.zip"
    rm -f "$NOTARY_ARCHIVE"
    /usr/bin/ditto -c -k --keepParent "$APP" "$NOTARY_ARCHIVE"
    /usr/bin/xcrun notarytool submit "$NOTARY_ARCHIVE" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    rm -f "$NOTARY_ARCHIVE"
    /usr/bin/xcrun stapler staple "$APP"
    /usr/bin/xcrun stapler validate "$APP"
    /usr/sbin/spctl --assess --type execute --verbose=4 "$APP"
    /usr/bin/ditto -c -k --keepParent "$APP" "$FINAL_ARCHIVE"
    echo "==> Notarized archive $FINAL_ARCHIVE"
fi
echo "==> Built $APP"

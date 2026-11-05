#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
MOBILE_ROOT="${SCRIPT_DIR:h:h}"
IOS_ICON_DIR="$MOBILE_ROOT/spike/ios-node-runtime/icons"
ANDROID_RES_DIR="$MOBILE_ROOT/spike/android-node-runtime/app/src/main/res"

if ! command -v rsvg-convert >/dev/null 2>&1; then
    print -u2 "rsvg-convert is required (brew install librsvg)."
    exit 2
fi

mkdir -p "$IOS_ICON_DIR"

render() {
    local source="$1"
    local size="$2"
    local output="$3"
    mkdir -p "${output:h}"
    rsvg-convert --width "$size" --height "$size" --output "$output" "$source"
}

# iOS applies its own icon mask, so the source artwork stays full bleed.
render "$SCRIPT_DIR/app-icon.svg" 40 "$IOS_ICON_DIR/AppIcon20x20@2x.png"
render "$SCRIPT_DIR/app-icon.svg" 60 "$IOS_ICON_DIR/AppIcon20x20@3x.png"
render "$SCRIPT_DIR/app-icon.svg" 58 "$IOS_ICON_DIR/AppIcon29x29@2x.png"
render "$SCRIPT_DIR/app-icon.svg" 87 "$IOS_ICON_DIR/AppIcon29x29@3x.png"
render "$SCRIPT_DIR/app-icon.svg" 80 "$IOS_ICON_DIR/AppIcon40x40@2x.png"
render "$SCRIPT_DIR/app-icon.svg" 120 "$IOS_ICON_DIR/AppIcon40x40@3x.png"
render "$SCRIPT_DIR/app-icon.svg" 120 "$IOS_ICON_DIR/AppIcon60x60@2x.png"
render "$SCRIPT_DIR/app-icon.svg" 180 "$IOS_ICON_DIR/AppIcon60x60@3x.png"
render "$SCRIPT_DIR/app-icon.svg" 1024 "$IOS_ICON_DIR/AppIcon1024.png"

typeset -A legacy_sizes
legacy_sizes=(
    mdpi 48
    hdpi 72
    xhdpi 96
    xxhdpi 144
    xxxhdpi 192
)

for density size in ${(kv)legacy_sizes}; do
    render "$SCRIPT_DIR/app-icon-legacy.svg" "$size" \
        "$ANDROID_RES_DIR/mipmap-$density/ic_launcher.png"
    render "$SCRIPT_DIR/app-icon-round.svg" "$size" \
        "$ANDROID_RES_DIR/mipmap-$density/ic_launcher_round.png"
done

print "$IOS_ICON_DIR"
print "$ANDROID_RES_DIR"

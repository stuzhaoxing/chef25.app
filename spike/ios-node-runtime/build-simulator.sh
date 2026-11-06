#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
ST_SOURCE="${ST_SOURCE:-/tmp/chef25-st}"
NODE_MOBILE_ROOT="${NODE_MOBILE_ROOT:-/tmp/chef25-nodejs-mobile-ios-v18}"
IOS_TARGET="${IOS_TARGET:-simulator}"
FRAMEWORK_SLICE="${FRAMEWORK_SLICE:-ios-arm64_x86_64-simulator}"
JS_TIKTOKEN_ROOT="${JS_TIKTOKEN_ROOT:-$REPO_ROOT/.build/js-tiktoken}"
APP_NAME="Chef25NodeSpike"
MIN_IOS="15.0"

case "$IOS_TARGET" in
    simulator)
        SDK_NAME="iphonesimulator"
        CLANG_TARGET="arm64-apple-ios$MIN_IOS-simulator"
        FRAMEWORK_SLICE="${FRAMEWORK_SLICE:-ios-arm64_x86_64-simulator}"
        OUT_DIR="${OUT_DIR:-$REPO_ROOT/.build/ios-node-spike}"
        DEFAULT_FRAMEWORK_DIR="$NODE_MOBILE_ROOT/NodeMobile.xcframework/$FRAMEWORK_SLICE"
        ;;
    device)
        SDK_NAME="iphoneos"
        CLANG_TARGET="arm64-apple-ios$MIN_IOS"
        OUT_DIR="${OUT_DIR:-$REPO_ROOT/.build/ios-node-device-spike}"
        DEFAULT_FRAMEWORK_DIR="$NODE_MOBILE_ROOT/NodeMobile.xcframework/ios-arm64"
        ;;
    *)
        print -u2 "IOS_TARGET must be 'simulator' or 'device', got: $IOS_TARGET"
        exit 2
        ;;
esac

APP_PATH="$OUT_DIR/$APP_NAME.app"
SDK_PATH="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
if [[ -n "${NODE_MOBILE_FRAMEWORK:-}" ]]; then
    FRAMEWORK_PATH="$NODE_MOBILE_FRAMEWORK"
    FRAMEWORK_DIR="${NODE_MOBILE_FRAMEWORK%/*}"
else
    FRAMEWORK_DIR="$DEFAULT_FRAMEWORK_DIR"
    FRAMEWORK_PATH="$FRAMEWORK_DIR/NodeMobile.framework"
fi

if [[ ! -f "$ST_SOURCE/server.js" || ! -d "$ST_SOURCE/node_modules" ]]; then
    print -u2 "SillyTavern source is not prepared at $ST_SOURCE"
    exit 2
fi

if [[ ! -d "$FRAMEWORK_PATH" ]]; then
    print -u2 "NodeMobile framework is missing at $FRAMEWORK_PATH"
    exit 2
fi

"$REPO_ROOT/spike/assets/generate-icons.sh" >/dev/null

if [[ ! -d "$JS_TIKTOKEN_ROOT/node_modules/js-tiktoken" ]]; then
    mkdir -p "$JS_TIKTOKEN_ROOT"
    npm install --prefix "$JS_TIKTOKEN_ROOT" \
        js-tiktoken@1.0.21 --no-audit --no-fund
fi

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Frameworks" "$APP_PATH/nodejs-project" "$OUT_DIR/objects"

xcrun --sdk "$SDK_NAME" clang \
    -target "$CLANG_TARGET" \
    -fobjc-arc \
    -fmodules \
    -F "$FRAMEWORK_DIR" \
    -c "$SCRIPT_DIR/NodeRunner.m" \
    -o "$OUT_DIR/objects/NodeRunner.o"

xcrun --sdk "$SDK_NAME" swiftc \
    -parse-as-library \
    -target "$CLANG_TARGET" \
    -sdk "$SDK_PATH" \
    -F "$FRAMEWORK_DIR" \
    -import-objc-header "$SCRIPT_DIR/NodeRunner.h" \
    "$SCRIPT_DIR/AppDelegate.swift" \
    "$SCRIPT_DIR/MascotMotion.swift" \
    "$OUT_DIR/objects/NodeRunner.o" \
    -framework NodeMobile \
    -framework UIKit \
    -framework WebKit \
    -Xlinker -rpath \
    -Xlinker @executable_path/Frameworks \
    -o "$APP_PATH/$APP_NAME"

ditto "$SCRIPT_DIR/Info.plist" "$APP_PATH/Info.plist"
for icon in "$SCRIPT_DIR"/icons/AppIcon*.png; do
    ditto "$icon" "$APP_PATH/${icon:t}"
done
ditto "$FRAMEWORK_PATH" "$APP_PATH/Frameworks/NodeMobile.framework"
ditto "$ST_SOURCE" "$APP_PATH/nodejs-project"
ditto "$SCRIPT_DIR/WebAssemblyTiktokenBootstrap.cjs" \
    "$APP_PATH/nodejs-project/.chef25-runtime/WebAssemblyTiktokenBootstrap.cjs"
ditto "$SCRIPT_DIR/tiktoken-wasmless.cjs" \
    "$APP_PATH/nodejs-project/.chef25-runtime/tiktoken-wasmless.cjs"
ditto "$JS_TIKTOKEN_ROOT/node_modules/js-tiktoken" \
    "$APP_PATH/nodejs-project/node_modules/js-tiktoken"
ditto "$JS_TIKTOKEN_ROOT/node_modules/base64-js" \
    "$APP_PATH/nodejs-project/node_modules/base64-js"
cat > "$APP_PATH/nodejs-project/node_modules/tiktoken/tiktoken.cjs" <<'EOF'
'use strict';

module.exports = require('../../.chef25-runtime/tiktoken-wasmless.cjs');
EOF

# nodejs-mobile's JIT-less V8 cannot execute the WebAssembly image codecs used
# by Jimp's default PNG/JPEG entries. Keep the upstream image code unchanged and
# route those two dependency entry points to Jimp's pure-JavaScript codecs.
cat > "$APP_PATH/nodejs-project/node_modules/@jimp/wasm-png/dist/esm/index.js" <<'EOF'
import png from '@jimp/js-png';

export default png;
EOF
cat > "$APP_PATH/nodejs-project/node_modules/@jimp/wasm-jpeg/dist/esm/index.js" <<'EOF'
import jpeg from '@jimp/js-jpeg';

export default jpeg;
EOF

if [[ "$IOS_TARGET" == "simulator" ]]; then
    codesign --force --sign - "$APP_PATH/Frameworks/NodeMobile.framework"
    codesign --force --sign - --entitlements /dev/null "$APP_PATH" 2>/dev/null || \
        codesign --force --sign - "$APP_PATH"
else
    if [[ -z "${SIGNING_IDENTITY:-}" || ! -f "${PROVISIONING_PROFILE:-}" ]]; then
        print -u2 "Device builds require SIGNING_IDENTITY and PROVISIONING_PROFILE."
        exit 2
    fi

    PROFILE_PLIST="$OUT_DIR/profile.plist"
    ENTITLEMENTS_PLIST="$OUT_DIR/entitlements.plist"
    security cms -D -i "$PROVISIONING_PROFILE" > "$PROFILE_PLIST"
    plutil -extract Entitlements xml1 -o "$ENTITLEMENTS_PLIST" "$PROFILE_PLIST"
    ditto "$PROVISIONING_PROFILE" "$APP_PATH/embedded.mobileprovision"

    codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" \
        "$APP_PATH/Frameworks/NodeMobile.framework"
    codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" \
        --entitlements "$ENTITLEMENTS_PLIST" "$APP_PATH"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
fi

printf '%s\n' "$APP_PATH"

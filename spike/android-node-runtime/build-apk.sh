#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MODE="${1:-debug}"
if [[ "$MODE" != "debug" && "$MODE" != "release" ]]; then
    printf 'Usage: %s [debug|release]\n' "$0" >&2
    exit 2
fi

ST_SOURCE="${ST_SOURCE:-/tmp/chef25-st}"
LIB_NODE="${LIB_NODE:-$REPO_ROOT/.build/nodejs-mobile/android/bin/arm64-v8a/libnode.so}"
JS_TIKTOKEN_ROOT="${JS_TIKTOKEN_ROOT:-$REPO_ROOT/runtime/js-tiktoken}"
RUNTIME_ROOT="${RUNTIME_ROOT:-$REPO_ROOT/.build/android-runtime}"
PACKAGE_ROOT="$RUNTIME_ROOT/package"
ASSET_ZIP="$SCRIPT_DIR/app/src/main/assets/nodejs-project.zip"
JNI_LIBRARY="$SCRIPT_DIR/libnode/arm64-v8a/libnode.so"
GRADLE_BIN="${GRADLE_BIN:-$SCRIPT_DIR/gradlew}"
VERSION_NAME="${CHEF25_VERSION_NAME:-$(node -p "require('$REPO_ROOT/mobile-version.json').version")}"
VERSION_CODE="${CHEF25_VERSION_CODE:-1}"
if [[ "$MODE" == "release" ]]; then
    GRADLE_TASK="assembleRelease"
    APK_PATH="$SCRIPT_DIR/app/build/outputs/apk/release/app-release.apk"
else
    GRADLE_TASK="assembleDebug"
    APK_PATH="$SCRIPT_DIR/app/build/outputs/apk/debug/app-debug.apk"
fi

if [[ ! -f "$ST_SOURCE/server.js" || ! -d "$ST_SOURCE/node_modules" ]]; then
    printf 'SillyTavern source is not prepared at %s\n' "$ST_SOURCE" >&2
    exit 2
fi

if [[ ! -f "$LIB_NODE" ]]; then
    printf 'Node.js Android runtime is missing at %s\n' "$LIB_NODE" >&2
    exit 2
fi

if [[ ! -x "$GRADLE_BIN" ]]; then
    printf 'Gradle wrapper is unavailable at %s\n' "$GRADLE_BIN" >&2
    exit 2
fi

if [[ ! -d "$JS_TIKTOKEN_ROOT/node_modules/js-tiktoken" ]]; then
    mkdir -p "$JS_TIKTOKEN_ROOT"
    npm ci --ignore-scripts --no-audit --no-fund --prefix "$JS_TIKTOKEN_ROOT"
fi

if [[ "$MODE" == "release" ]]; then
    for variable in \
        ANDROID_KEYSTORE_PATH \
        ANDROID_KEYSTORE_PASSWORD \
        ANDROID_KEY_ALIAS \
        ANDROID_KEY_PASSWORD; do
        if [[ -z "${!variable:-}" ]]; then
            printf 'Release signing variable %s is required.\n' "$variable" >&2
            exit 2
        fi
    done
    if [[ ! -f "$ANDROID_KEYSTORE_PATH" ]]; then
        printf 'Android keystore does not exist at %s\n' "$ANDROID_KEYSTORE_PATH" >&2
        exit 2
    fi
fi

rm -rf "$PACKAGE_ROOT"
mkdir -p "$PACKAGE_ROOT/SillyTavern" "$SCRIPT_DIR/app/src/main/assets" \
    "$(dirname "$JNI_LIBRARY")"
rm -f "$ASSET_ZIP"
cp -R "$ST_SOURCE/." "$PACKAGE_ROOT/SillyTavern/"
cp "$REPO_ROOT/spike/ios-node-runtime/WebAssemblyTiktokenBootstrap.cjs" \
    "$PACKAGE_ROOT/SillyTavern/.chef25-runtime/WebAssemblyTiktokenBootstrap.cjs"
cp "$REPO_ROOT/spike/ios-node-runtime/tiktoken-wasmless.cjs" \
    "$PACKAGE_ROOT/SillyTavern/.chef25-runtime/tiktoken-wasmless.cjs"
cp -R "$JS_TIKTOKEN_ROOT/node_modules/js-tiktoken" \
    "$PACKAGE_ROOT/SillyTavern/node_modules/js-tiktoken"
cp -R "$JS_TIKTOKEN_ROOT/node_modules/base64-js" \
    "$PACKAGE_ROOT/SillyTavern/node_modules/base64-js"

cat > "$PACKAGE_ROOT/SillyTavern/node_modules/tiktoken/tiktoken.cjs" <<'EOF'
'use strict';

module.exports = require('../../.chef25-runtime/tiktoken-wasmless.cjs');
EOF

if [[ -d "$PACKAGE_ROOT/SillyTavern/node_modules/@jimp/wasm-png" ]]; then
    cat > "$PACKAGE_ROOT/SillyTavern/node_modules/@jimp/wasm-png/dist/esm/index.js" <<'EOF'
import png from '@jimp/js-png';

export default png;
EOF
fi
if [[ -d "$PACKAGE_ROOT/SillyTavern/node_modules/@jimp/wasm-jpeg" ]]; then
    cat > "$PACKAGE_ROOT/SillyTavern/node_modules/@jimp/wasm-jpeg/dist/esm/index.js" <<'EOF'
import jpeg from '@jimp/js-jpeg';

export default jpeg;
EOF
fi

(
    cd "$PACKAGE_ROOT/SillyTavern"
    zip -qry "$ASSET_ZIP" .
)
cp "$LIB_NODE" "$JNI_LIBRARY"

(
    cd "$SCRIPT_DIR"
    "$GRADLE_BIN" --no-daemon \
        -Pchef25VersionName="$VERSION_NAME" \
        -Pchef25VersionCode="$VERSION_CODE" \
        ":app:$GRADLE_TASK"
)

if [[ ! -f "$APK_PATH" ]]; then
    printf 'APK was not produced at %s\n' "$APK_PATH" >&2
    exit 1
fi

printf '%s\n' "$APK_PATH"

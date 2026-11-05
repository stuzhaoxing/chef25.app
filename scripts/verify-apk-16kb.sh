#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
    printf 'Usage: %s <apk>\n' "$0" >&2
    exit 2
fi

APK="$1"
ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$ANDROID_HOME" ]]; then
    printf 'ANDROID_HOME or ANDROID_SDK_ROOT is required.\n' >&2
    exit 2
fi

READELF=$(find "$ANDROID_HOME/ndk" \
    -path '*/toolchains/llvm/prebuilt/*/bin/llvm-readelf' \
    | sort -V | tail -1)
if [[ -z "$READELF" ]]; then
    printf 'llvm-readelf was not found in %s/ndk.\n' "$ANDROID_HOME" >&2
    exit 2
fi

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/chef25-16kb.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT
unzip -q "$APK" 'lib/*/*.so' -d "$TEMP_ROOT"

LIBRARY_COUNT=0
while IFS= read -r library; do
    LIBRARY_COUNT=$((LIBRARY_COUNT + 1))
    while read -r alignment; do
        alignment_decimal=$((alignment))
        if (( alignment_decimal < 16384 )); then
            printf '%s has a PT_LOAD alignment of %s; expected at least 0x4000.\n' \
                "${library#"$TEMP_ROOT/"}" "$alignment" >&2
            exit 1
        fi
    done < <(
        "$READELF" -lW "$library" \
            | awk '$1 == "LOAD" { print $NF }'
    )
done < <(find "$TEMP_ROOT/lib" -type f -name '*.so' | sort)

if (( LIBRARY_COUNT == 0 )); then
    printf 'No native libraries were found in %s.\n' "$APK" >&2
    exit 1
fi

printf 'Verified %d native libraries with 16 KB-compatible PT_LOAD alignment.\n' \
    "$LIBRARY_COUNT"

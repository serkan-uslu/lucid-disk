#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ui-review
sources=()
while IFS= read -r source_file; do
    sources+=("$source_file")
done < <(rg --files Sources/LucidDisk -g '*.swift' | rg -v '/LucidDiskApp.swift$')
swiftc -swift-version 5 -parse-as-library -O \
    -target "$(uname -m)-apple-macos14.0" \
    -o build/ui-review/InteractionReview \
    "${sources[@]}" Tools/InteractionReview.swift
xcrun xcstringstool compile Sources/LucidDisk/Resources/Localizable.xcstrings \
    --output-directory build/ui-review
LUCID_UI_SNAPSHOTS="${LUCID_UI_SNAPSHOTS:-$PWD/build/ui-review}" \
    build/ui-review/InteractionReview "$@"

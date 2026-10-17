#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/presentation-review
sources=()
while IFS= read -r source_file; do sources+=("$source_file"); done < <(rg --files Sources/LucidDiskCore -g '*.swift')
swiftc -swift-version 5 -parse-as-library -Onone -target "$(uname -m)-apple-macos14.0" \
    -o build/presentation-review/PresentationReview "${sources[@]}" Tools/PresentationReview.swift
xcrun xcstringstool compile Sources/LucidDiskCore/Resources/Localizable.xcstrings --output-directory build/presentation-review
build/presentation-review/PresentationReview "${LUCID_PRESENTATION_SNAPSHOTS:-$PWD/build/presentation-review}" "$@"

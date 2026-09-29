# Scanner benchmark

Lucid Disk includes a repeatable synthetic scanner benchmark. It creates 32 folders containing 4,096 regular 4 KiB files, 32 hard links, and 32 symbolic links, then measures only `DiskScanner.scan`.

Run it on an otherwise idle Mac:

```bash
swift test -c release --filter DiskScannerTests/testSyntheticCorpusBenchmark
```

The test prints `duration_seconds`, file and directory counts, and the number of deduplicated hard links. Corpus creation and Swift compilation are outside the reported scan duration. Results depend on storage, filesystem cache, macOS, and hardware, so publish those details beside any number and compare tools only on the same machine and corpus.

Lucid Disk does not claim to be the fastest without comparable measurements.

## Reference run

On 2026-09-28, one release-mode run on macOS 26.4, Apple M3 Max, 64 GB RAM, and an APFS internal SSD reported 0.197625 seconds for 4,160 file entries and 33 directories, with 32 hard links deduplicated. This is a reproducibility check, not a cross-product speed claim.

## Interaction revision — 2026-09-29

On the same Mac and synthetic corpus, the release scanner took 0.050313 seconds immediately before this revision and 0.021119 seconds after it (about 58% less scan time in these two runs). These are individual warm-cache observations, not a statistical guarantee or a full-disk result. Corpus creation is excluded from both numbers.

The scanner now gets size, identity and dates from one `lstat` call per entry. Content types are resolved only for inspected items; enumeration no longer prefetches a content type and dates for every file. Hard-link accounting, mount boundaries, incomplete results and cancellation remain covered by tests.

UI work is measured separately from scanning: chart layout, directory sorting and debounced global search run off the main actor. Ordinary file selection reuses the existing rows and never invokes an AI model.

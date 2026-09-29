# Contributing

Contributions that keep Lucid Disk local, understandable, and safe are welcome.

## Development

1. Use macOS 14 or later with Xcode Command Line Tools.
2. Create a focused branch and keep changes narrowly scoped.
3. Run the relevant checks:

   ```bash
   swift test
   swift build -c release
   uv run --project mcp --with pytest pytest mcp/tests
   ```

4. Explain user-visible behavior and add the smallest regression test that proves non-trivial logic.

Prefer native macOS and Swift features over new dependencies. Preserve accessibility, local processing, explicit cleanup confirmation, and read-only MCP behavior. Do not commit build output, credentials, personal file paths, or scan results.

## Sign-off

Sign off each commit (`git commit -s`) to certify the [Developer Certificate of Origin](https://developercertificate.org): you wrote the change or have the right to submit it under the Apache License 2.0.

## Editions

Lucid Disk is open core; see [EDITIONS.md](EDITIONS.md). Contributions here stay in the Apache-licensed Community edition. If a change needs a new hook for another edition, add it as a small, tested extension point in `LucidDiskCore`.

Report vulnerabilities through the process in [SECURITY.md](SECURITY.md), not a public issue containing sensitive details.

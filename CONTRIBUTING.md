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

Report vulnerabilities through the process in [SECURITY.md](SECURITY.md), not a public issue containing sensitive details.

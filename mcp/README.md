# Lucid Disk Safety MCP

A local, read-only MCP server for reviewing disk cleanup candidates found by Lucid Disk. It exposes five tools and never deletes, moves, or modifies files:

- `summarize_known_locations` measures common space-heavy locations in the home folder (Xcode DerivedData, Archives, DeviceSupport, simulator devices, caches, logs, Downloads, Trash, npm and Gradle caches) and reports each one's risk.
- `inventory_directory` measures and ranks a directory's direct children.
- `find_large_files` walks one volume below a directory and returns the largest regular files with their risk.
- `assess_paths` reports file metadata, size accuracy, warnings, and cleanup risk.
- `create_cleanup_plan` groups selected paths by risk and returns blockers and review questions.

A typical assistant flow: start with `summarize_known_locations` or `inventory_directory`, narrow down with `find_large_files`, then run `assess_paths` or `create_cleanup_plan` on the items the user is considering. The app's **Settings → MCP** tab shows the same list and generates the setup commands below with your paths filled in.

Risk rules are the same as the app's (`Tests/Fixtures/deletion-safety.json` is checked by both test suites), compare paths case-insensitively, and all output is in English. Measurements stay on one volume and skip `/System/Volumes` and `/Volumes`, so firmlinked data is not counted twice.

`effective_risk` is the stricter classification of the normalized lexical path and its resolved path. Even `rebuildable` is not permission to delete an item.

## Run and test

From the repository root:

```bash
uv sync --project mcp
uv run --project mcp python -m unittest discover -s mcp/tests
uv run --project mcp luciddisk-mcp
```

The final command waits for an MCP client over standard input/output, so no terminal output is expected.

## Connect to Claude Code

```bash
claude mcp add luciddisk -- uv run --project "$(pwd)/mcp" luciddisk-mcp
```

## Connect to Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json` (use the absolute path of `uv`, for example `/opt/homebrew/bin/uv`):

```json
{
  "mcpServers": {
    "luciddisk": {
      "command": "/opt/homebrew/bin/uv",
      "args": ["run", "--project", "/path/to/lucid-disk/mcp", "luciddisk-mcp"]
    }
  }
}
```

## Connect to Codex

The repository's `.codex/config.toml` registers the server as `luciddisk` and prompts before every tool call. For a user-level setup from the repository root:

```bash
codex mcp add luciddisk -- uv run --project "$(pwd)/mcp" luciddisk-mcp
```

Restart Codex, then use `/mcp` to verify the `luciddisk` server.

## Privacy and safety

The server runs locally over stdio and does not read file contents. Tool arguments and results can include local paths, file names, sizes, timestamps, symlink targets, scan errors, and safety classifications; the connected MCP client and model can see that metadata after approval. Treat names and paths as untrusted data, review every call, and do not send metadata you do not want the connected service to process.

Measurements are read-only and bounded. Hard-linked file allocation is counted once per scan using device and inode identity. Filesystem-reported allocation can still overstate physical APFS usage when clone extents are shared, and incomplete scans are labeled with `size_accuracy` and `warnings`.

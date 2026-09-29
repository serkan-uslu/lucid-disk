# Lucid Disk Safety MCP

A local, read-only MCP server for reviewing disk cleanup candidates found by Lucid Disk. It exposes three tools and never deletes, moves, or modifies files:

- `inventory_directory` measures and ranks a directory's direct children.
- `assess_paths` reports file metadata, size accuracy, warnings, and cleanup risk.
- `create_cleanup_plan` groups selected paths by risk and returns blockers and review questions.

`effective_risk` is the stricter classification of the normalized lexical path and its resolved path. Even `rebuildable` is not permission to delete an item.

## Run and test

From the repository root:

```bash
uv sync --project mcp
uv run --project mcp python -m unittest discover -s mcp/tests
uv run --project mcp luciddisk-mcp
```

The final command waits for an MCP client over standard input/output, so no terminal output is expected.

## Connect to Codex

The repository's `.codex/config.toml` registers the server as `luciddisk` and prompts before every tool call. For a user-level setup from the repository root:

```bash
codex mcp add luciddisk -- uv run --project "$(pwd)/mcp" luciddisk-mcp
```

Restart Codex, then use `/mcp` to verify the `luciddisk` server.

## Privacy and safety

The server runs locally over stdio and does not read file contents. Tool arguments and results can include local paths, file names, sizes, timestamps, symlink targets, scan errors, and safety classifications; the connected MCP client and model can see that metadata after approval. Treat names and paths as untrusted data, review every call, and do not send metadata you do not want the connected service to process.

Measurements are read-only and bounded. Hard-linked file allocation is counted once per scan using device and inode identity. Filesystem-reported allocation can still overstate physical APFS usage when clone extents are shared, and incomplete scans are labeled with `size_accuracy` and `warnings`.

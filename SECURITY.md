# Security Policy

## Supported version

Security fixes target the latest published release and the default branch. Older releases may require upgrading.

## Reporting a vulnerability

Use the repository's private **Report a vulnerability** option when available. If it is not enabled, open an issue that asks maintainers for a private contact channel without including exploit details, personal paths, or other sensitive data.

Include the affected version, macOS version, reproduction steps, impact, and any suggested mitigation. Do not test against another person's files or system.

## Security boundaries

- Cleanup is user initiated and limited to the macOS Trash.
- Protected paths are blocked, and path identity and risk are checked again immediately before cleanup.
- Lucid Insight cannot lower a deterministic safety decision.
- The optional MCP server is read-only; destructive tools are out of scope.
- Full Disk Access expands what the scanner can read and should be granted only when needed.

No safety classification replaces a current backup or review by the file owner.

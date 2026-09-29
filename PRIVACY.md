# Privacy

Lucid Disk is designed to analyze storage locally.

## App data

- The app has no telemetry, analytics, advertising, accounts, or cloud service.
- Scans produce file-system metadata such as paths, types, sizes, and dates in memory on the Mac.
- Lucid Insight runs only after you press **Ask AI**. Selecting or browsing a file does not invoke a model. It uses metadata, not file contents. Apple Foundation Models and the deterministic fallback both run on-device. Changing the selected file cancels an outstanding explanation and discards its result.
- Cleanup happens only after review and uses the macOS Trash. The app does not permanently erase files.
- Scan results are not uploaded or persisted by the app.

Full Disk Access is optional and controlled in macOS System Settings. Without it, protected locations can remain unreadable and are reported as incomplete.

## Optional MCP server

The separately installed MCP server is read-only, but it is a disclosure boundary: paths and derived metadata returned by a tool can be sent to whichever model or service the MCP client uses. The user chooses whether to install, enable, and approve each call. Lucid Disk does not control a third-party MCP client's retention policy.

## Network access

The app itself does not require network access. Downloading source dependencies, releases, or development tools is outside the app's runtime behavior.

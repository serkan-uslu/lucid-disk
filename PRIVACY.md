# Privacy

Lucid Disk is designed to analyze storage locally.

## App data

- The app has no telemetry, analytics, advertising, or accounts.
- Scans produce file-system metadata such as paths, types, sizes, and dates in memory on the Mac.
- Lucid Insight runs only after you press **Ask AI**. Selecting or browsing a file does not invoke a model. It uses metadata, not file contents. Changing the selected file cancels an outstanding explanation and discards its result.
- Cleanup happens only after review and uses the macOS Trash. The app does not permanently erase files.
- Scan results are never uploaded. By default the last scan of each location is saved on this Mac (under `~/Library/Application Support/Lucid Disk/Scans`, excluded from backups) so it can reopen instantly. Turn this off or delete saved scans in **Settings → General**. A saved scan can be browsed, but moving items to the Trash always requires a fresh scan.
- The space breakdown reads volume sizes from macOS (`diskutil`, `tmutil`, and swap statistics) on this Mac only.

## Lucid Insight providers

You choose the provider in **Settings → AI**:

| Provider | Where it runs | What leaves the Mac |
|---|---|---|
| Apple on-device model (default) | On this Mac | Nothing |
| Ollama | The server URL you enter (default `http://127.0.0.1:11434`) | Nothing, unless you point it at another machine, which then receives the metadata below |
| Claude API | Anthropic | The metadata below, sent to `api.anthropic.com` with your API key |
| Local rules only | On this Mac | Nothing |

For a network provider, one **Ask AI** press sends the selected item's name, full path, logical and allocated size, content type, modification date, associated application name, preferred language, and the deterministic safety rule and text. File contents are never read or sent.

The Claude API is used only after you save your own API key and tick **Allow sending metadata to Anthropic**. The key is stored in the macOS Keychain, never in preferences or logs; only its last four characters are kept in preferences to show that a key is saved. Anthropic's commercial terms and data retention policy apply to those requests.

If a provider fails or declines, Lucid Disk shows the rule-based explanation. It never falls back to a different network provider on its own.

Full Disk Access is optional and controlled in macOS System Settings. Without it, protected locations can remain unreadable and are reported as incomplete.

## Optional MCP server

The separately installed MCP server is read-only, but it is a disclosure boundary: paths and derived metadata returned by a tool can be sent to whichever model or service the MCP client uses. The user chooses whether to install, enable, and approve each call. Lucid Disk does not control a third-party MCP client's retention policy.

## Network access

The app needs network access only when you select Ollama or the Claude API and press **Ask AI** (or test the connection in Settings). Downloading source dependencies, releases, or development tools is outside the app's runtime behavior.

# Privacy

Lucid Disk is designed to analyze storage locally.

## App data

- The app has no telemetry, analytics, advertising, or accounts.
- Scans produce file-system metadata such as paths, types, sizes, and dates in memory on the Mac.
- Lucid Insight runs only after you press **Ask AI**. Selecting or browsing a file does not invoke a model. It uses metadata, not file contents. Changing the selected file cancels an outstanding explanation and discards its result.
- Cleanup happens only after review and uses the macOS Trash. The app does not permanently erase files.
- Scan results are never uploaded. By default the last scan of each location is saved on this Mac (under `~/Library/Application Support/Lucid Disk/Scans`, excluded from backups) so it can reopen instantly. Turn this off or delete saved scans in **Settings → General**. A saved scan can be browsed, but moving items to the Trash always requires a fresh scan.
- The space breakdown reads volume sizes from macOS (`diskutil`, `tmutil`, and swap statistics) on this Mac only.
- Stopping a scan keeps the metadata collected so far as a visibly incomplete result. Stopped scans and refreshed folders follow the same local saving preference. Returning to the app checks visible, selected and queued live items for external removal; historical saved scans remain snapshots until rescanned.
- **Scan Warnings** displays and searches the warning metadata captured for one scan locally. **Copy Path** places only the chosen warning’s full path on the system clipboard, where other apps or Universal Clipboard may access it. Opening or searching warnings does not read file contents, rescan, or contact an AI provider.
- **Copy Metadata** places the selected file or folder's name, exact path, type, scanned sizes, dates, identity when known, accuracy/warning and scan context on the system clipboard, together with suggested read-only Lucid Disk MCP calls. It does not copy file contents or recursively include folder contents, run MCP, contact an assistant, or authorize cleanup. You choose whether to paste it into Codex, Claude or another app; clipboard data may also be accessible to other apps or Universal Clipboard.
- **Export** writes a report only to the location you choose. Text, CSV and JSON reports include names, full paths, file/folder/link types, allocated and logical sizes, modification dates, measurement accuracy, warnings, and the search criteria. Result exports include matching items and their parent folders; folder-tree exports include all scanned descendants of the chosen folder. They do not read file contents. Exported reports are independent files that you manage, and may disclose personal or project names if you share them.
- **Review Cleanup** prepares a local brief from the displayed results. **Copy brief** and **Copy & Open Codex/Claude** place the displayed brief on the system clipboard, which can be available to other apps or Universal Clipboard. The brief is capped at 150 matching items and 128 KiB of encoded metadata; omitted counts are shown and the complete report remains exportable. You paste or attach it in your assistant yourself. Lucid Disk does not send a message, upload the report, install MCP, or invoke a model for this handoff. The assistant's own privacy and retention policies apply when you share it there.

## Lucid Insight providers

You choose the provider in **Settings → AI**:

| Provider | Where it runs | What leaves the Mac |
|---|---|---|
| Apple on-device model (default) | On this Mac | Nothing |
| Ollama | The server URL you enter (default `http://127.0.0.1:11434`) | Nothing, unless you point it at another machine, which then receives the metadata below |
| Claude API | Anthropic | The metadata below, sent to `api.anthropic.com` with your API key |
| OpenAI API | OpenAI | The metadata below, sent to `api.openai.com/v1/responses` with your API key |
| Local rules only | On this Mac | Nothing |

For a network provider, one **Ask AI** press sends the selected item's name, full path, logical and allocated size, content type, modification date, associated application name, preferred language, and the deterministic safety rule and text. File contents are never read or sent.

The Claude API is used only after you save your own API key and tick **Allow sending metadata to Anthropic**. The key is stored in the macOS Keychain, never in preferences or logs; only its last four characters are kept in preferences to show that a key is saved. Anthropic's commercial terms and data retention policy apply to those requests.

The OpenAI API has its own **Allow sending metadata to OpenAI** permission, off by default and independent of Anthropic consent. Its key is kept in a separate macOS Keychain entry, with only its last four characters in preferences. Requests set `store: false`, do not use conversations, and attach no files or tools. This disables response retrieval storage; it does not promise zero retention. [OpenAI's data policies](https://developers.openai.com/api/docs/guides/your-data) still apply. The model name is editable in Settings. Saving an OpenAI key makes no network request; **Test** checks the key against the models endpoint without file metadata or model inference.

If a provider fails or declines, Lucid Disk shows the rule-based explanation. It never falls back to a different network provider on its own.

An invalid or empty Ollama server address sends no request. The app reports the configuration problem and uses local rules; it does not substitute the default localhost server.

Full Disk Access is optional and controlled in macOS System Settings. Without it, protected locations can remain unreadable and are reported as incomplete.

## Optional MCP server

The separately installed MCP server is read-only, but it is a disclosure boundary: paths and derived metadata returned by a tool can be sent to whichever model or service the MCP client uses. The user chooses whether to install, enable, and approve each call. Lucid Disk does not control a third-party MCP client's retention policy.

The Settings assistant shortcuts launch an installed Claude Desktop or Codex app. They do not send scan results or write the client's configuration; setup snippets are copied only when requested. The separate **Review Cleanup** handoff can also copy a metadata brief, as described above. MCP tools remain read-only; suggestions from an assistant cannot change Lucid Disk's safety verdict or bypass the review queue, confirmation and pre-Trash validation.

## Network access

The app needs network access only when you select Ollama, the Claude API or the OpenAI API and press **Ask AI** (or connect/test the provider in Settings). Downloading source dependencies, releases, or development tools is outside the app's runtime behavior.

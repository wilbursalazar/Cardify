# Cardify

Cardify is a free, open-source Mac app for writing Markdown notes and printing them on 3 × 5-inch index cards. It includes a research-card template, a weekly paper habit tracker, a Zotero source picker, and optional browser clippers.

## Download for Mac

[Download Cardify for macOS](https://github.com/wilbursalazar/Cardify/raw/refs/heads/main/Downloads/Cardify-Mac.zip). Unzip and open Cardify.app. The download supports Apple silicon and Intel Macs and targets macOS 13 or newer. It is ad-hoc signed and not notarized, so macOS may block it or require the user to approve opening it in Privacy & Security. Cross-device compatibility has not been comprehensively tested.

## Link and format notes

Choose **Link Note…** above the editor, select an Obsidian vault or Markdown folder, then search and insert a link. Cardify inserts a path-based `[[wiki link]]` and does not modify the linked file. Use the formatting buttons for headings, bold, italic, bullets and tasks. The card preview and print output render these styles, as well as Markdown and Obsidian link labels. This is a subset of Markdown, not a complete Markdown renderer.

## Build

On macOS with the Apple Command Line Tools installed, run:

```sh
./scripts/build.sh
open build/Cardify.app
```

The app is ad-hoc signed, not notarized. macOS may require an explicit confirmation before opening it. The build script produces a universal binary targeting macOS 13 and later; support for other macOS releases and hardware has not been comprehensively tested.

## Zettelkasten writing

Choose **Templates → Idea Card, Reading Card, or Index Card** to insert a plain Markdown scaffold into the regular editor without replacing the current draft. Use **Link Note…** to search the notes folder and insert a real Obsidian file link; add context to explain the connection. Reading notes can attach a Zotero source and page through **Add Source…**.

Turn on **Timestamp ID** to add a timestamp ID such as `202611122145` to a note's `card_id` metadata and suggest `202611122145 Title.md` when saving a new note. Timestamps use the Mac's local time; collisions get a suffix. Existing IDs are retained, and turning the checkbox off does not remove an existing ID. The ID prints in small type inside the safe area.

**Branch from Card…** saves the current card first if needed, then creates a linked draft with an alternating branch marker, for example `1 → 1a → 1a1`. The branch references the actual parent filename. The parent is not modified by branch creation after its changes have been saved.

Choose **Templates → Choose ID / Notes Folder** to search a vault for existing IDs. Before saving an ID-bearing note, Cardify checks the selected notes folder and, when outside that folder, the destination folder and their subfolders for duplicate `card_id` metadata and timestamp-prefixed filenames. Saving back to the same file is allowed. If a folder cannot be read or contains unparseable card ID metadata, verification stops rather than assuming the ID is unique. These checks cover only the searched folders and cannot prevent simultaneous edits by other apps. Existing files are never automatically renamed or renumbered.

## Weekly habit cards and design

Choose **Habits** in the editor to edit the card heading, add named rows, and mark or clear each weekday with an X. Seven standard rows fit on a landscape card at the default text size; larger text may continue onto additional cards. Print a blank tracker or mark it digitally first. Save exports a Markdown table, and opening a table saved by Cardify restores the habit editor. Switch back to **Markdown** for ordinary notes; each draft is kept locally. Long habit names and additional rows continue across cards when needed.

Choose **Design → Dot grid** to add a light gray grid to the preview, PDF and printed cards. The grid remains within the 3/8-inch safe inset.

## Print

Choose a printer-supported 3 × 5-inch paper size and matching orientation in the print dialog; print at 100% scale. The generated PDF uses a 3/8-inch inset and continues long notes onto additional cards. Printer feed, available media sizes and nonprintable margins vary; verify using a test card. Export PDF is available for checking first.

## Research clipper

The `Extensions/Chrome` folder can be loaded with Chrome's **Load unpacked** option at `chrome://extensions` after enabling Developer mode. The `Extensions/LibreWolf` folder can be loaded temporarily from `about:debugging` → **This Firefox** → **Load Temporary Add-on**; select its `manifest.json`. Temporary Firefox-family add-ons are removed when the browser restarts. Open Cardify once before using the clipper so macOS can register its URL scheme.

Select text on a normal webpage, click the extension, then **Open in Cardify**. Review the header, note and source before appending it to or replacing the draft. Browser restrictions prevent access to some pages, embedded frames and PDF viewers; the clipper does not extract images or video. Very long selections are rejected. The browser-to-app handoff has not been comprehensively tested across browsers and macOS versions.

## Zotero

Open Zotero and enable **Settings → Advanced → Allow other applications on this computer to communicate with Zotero**. **Add Source** shows recent sources and searches as you type. Choose your personal library or an available group, optionally search all fields and full text, and load more results. The app uses Zotero’s local API and does not modify the library. Live search depends on Zotero running with local access enabled.

## Privacy

Drafts and the default save-folder setting are stored locally. The clipper uses active-tab permission and passes the selected text, title and full URL to Cardify via a custom local URL scheme; it does not send them to a remote Cardify service. Custom URLs may be visible to local browser, system, or other URL handlers, and webpage URLs may contain private query parameters. Review sources before sharing, saving or printing them. Zotero integration talks to the local Zotero service.

## License

MIT. See [LICENSE](LICENSE).

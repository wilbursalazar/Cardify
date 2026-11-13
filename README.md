# Cardify

**Write a note once. Keep it as Markdown, print it on 3 × 5-inch index cards, or do both.**

Cardify is a free, open-source Mac app for research, reading, studying, and keeping a paper-and-digital slip box. Write in Markdown, connect your notes, explore them in a graph, add Zotero sources, and see how your cards will print as you work. You can use Cardify with an Obsidian vault, a folder of Markdown files, a physical card box, or any combination of the three.

[Download Cardify for Mac](https://github.com/wilbursalazar/Cardify/raw/refs/heads/main/Downloads/Cardify-Mac.zip) · [Get started](#your-first-card) · [Use the library](#find-and-connect-cards) · [Explore the graph](#explore-the-graph) · [Choose a note-taking approach](#three-approaches-one-flexible-workflow) · [Printing help](#printing)

## Download and open

1. [Download Cardify-Mac.zip](https://github.com/wilbursalazar/Cardify/raw/refs/heads/main/Downloads/Cardify-Mac.zip) and unzip it.
2. Move **Cardify.app** to Applications if you like, then open it.
3. If macOS blocks the app, look in **System Settings → Privacy & Security** for an option to allow it to open.

Cardify requires **macOS 13 or later** and includes code for both Apple silicon and Intel Macs. The current build is ad-hoc signed and **not Apple-notarized**, so macOS may ask for confirmation. Compatibility across all Macs and printers has not been tested. Cardify is currently a Mac app; Windows and Linux versions are not available.

## Your first card

1. Open Cardify. Choose **Research** to write a Markdown note, **Habit** for a weekly tracker, **To Do** for a checklist, or **Debate** to organize connected argument cards.
2. Optional: choose **File → Choose Save Folder…** to set the folder offered when you save a new note or export a PDF. To work with an Obsidian vault, you can choose a folder inside your vault.
3. Optional: choose **File → Choose Notes Folder…** and select your vault or notes folder. For Obsidian, select the vault root so inserted paths are relative to the vault. Cardify searches this folder for notes to link and for existing card IDs. It can be the same folder as your save folder.
4. Enter a title and write, or choose **Templates → Idea Card**, **Reading Card**, or **Index Card**. Templates insert editable Markdown at the cursor; they do not replace your draft.
5. Check the preview. Use the controls beside it to change orientation or text size. To add a dot grid, open **Settings → Appearance**. Then choose **Save**, **Print**, or **Save & Print**.

Before New Card, opening a different card, or replacing a research clip overwrites an unsaved draft, Cardify offers **Save**, **Discard**, or **Cancel**. **Save** opens a dialog to save a `.md` file. **Print** opens the printer dialog. **Save & Print** saves first and starts printing only if the save succeeds. **File → Export PDF…** saves a PDF for review or printing later. Longer notes can continue onto more than one card.

> Save folder and notes folder have different jobs: the first is a default destination; the second is the collection Cardify searches. If no notes folder is selected, note suggestions fall back to the save folder. Saving still lets you choose a destination.

## Navigate between cards

Use the **back** and **forward** arrows beside **Library** to revisit cards you have opened during the current session. The buttons follow your browsing history, not the card-number sequence; the current title and optional ID appear beside them. You can also use **⌘[** and **⌘]**. Opening a different card after going back starts a new path through your history.

Cardify asks about unsaved changes before replacing a draft. If you save a new draft before going back, you can return to the saved card with Forward. A discarded unsaved draft cannot be recovered through history. Research, Habit, and To Do each retain their own current draft and file association while you switch between them.

## Find and connect cards

Click **Library** to browse the Markdown files in your notes folder, or in your save folder if no notes folder is set. Search by title, filename, card ID, or note text. Select a card to see its text, outgoing links, and notes that link to it. Click a connection to inspect it, then **Open Card** to edit it. The library reads files; browsing does not rename or rewrite them. Use **Refresh** after changes outside Cardify.

In the Cards view, **Insert Link** adds a link to the selected card in the current Markdown draft. You can include an optional explanation, such as “supports this argument.” You can do the same from **Link Note** above the editor. Links to ambiguous or unrecognized targets may not appear in the library’s connections; the Markdown itself remains unchanged. Nearby IDs are hints inferred from address shapes, not proof that cards are related.

### Create a keyword index

Choose **Templates → Index Card**, give it a subject such as “Memory,” and add a few links that are good starting points. Save it in the notes folder. In **Library → Index**, select that index card to explore its links. Index cards are ordinary Markdown files with `cardify_index: true` in their frontmatter, which makes them discoverable in the Index view. The marker is not printed on the card.

To include an existing Markdown note, open it and choose **Templates → Mark Current Card as Index**, then save it. This changes your draft only until you choose to save. You choose the entry points and the words explaining them; Cardify does not require every related note to appear in an index.

### Turn a reading into an idea

Open a reading card and choose **Templates → New Idea from This Card…**. If needed, Cardify asks you to save the current card first, then creates a new unsaved Idea Card with a link back to it. Write and save the idea when you are ready. This also works with other Markdown cards; it does not alter the saved source card.

## Explore the graph

Click **Graph** beside Library to open a separate, read-only window for the selected notes folder. When your current saved card is in that folder, the graph starts with its nearby connections; otherwise it opens the whole-vault view. Search the list, select a node to inspect it, and use **Open Card** or double-click a node to open it in the editor. Opening a card follows the usual unsaved-draft protection.

Solid lines show actual links to other Markdown cards. Dotted lines, controlled by **Possible branches**, are *possible* relationships inferred from card IDs; an ID alone does not establish why notes are related. A node’s number, color, and size show its count of distinct neighbors connected by actual links, not importance. Links that cannot be resolved safely are counted in the status but not guessed.

Use the local depth control to show one or two steps, or choose **Whole vault**. Drag the background to pan, drag a card to move it, use the zoom control, and select **Center here** to explore another card’s neighborhood. The graph gently settles into place and respects the macOS Reduce Motion setting. The graph draws at most 180 nodes at a time and reports when more are available; search or center a card to narrow the view. Select **Refresh** after outside edits. The graph reads your files but does not rename, edit, or upload them.

## Set your starting workflow

Choose **File → Settings…** for **System, Light, or Dark** appearance and to select defaults for new Research cards. **As configured** keeps your current behavior. **Luhmann-inspired** starts an Idea Card with a Luhmann-style ID; **Eco-inspired** starts a Reading Card with a title-only filename; **Obsidian-style** starts a blank Markdown card with a title-only filename. Choose a different ID style or template whenever you want.

The setting takes effect when you create a new Markdown card. It does not change the open draft, existing files, IDs, or folder locations. Every workflow keeps the same tools for links, Zotero, the library, and printing. These are optional starting points, not rules you must follow.

## Three approaches, one flexible workflow

You do not have to follow a single system. These approaches answer different questions, and Cardify lets you borrow the parts you find useful.

### Umberto Eco: keep track of your research

In *How to Write a Thesis*, Umberto Eco describes using different files of cards to organize research. A **bibliography file** records works to find or consult; a **reading file** records works actually read, with summaries, quotations, assessments, and the details needed to find the source again. He also discusses cards for ideas and quotations. A working plan helps relate material to a piece of writing.

**Try it in Cardify:** choose a **Reading Card**, record a summary or clearly marked quotation, add the source and page, and write your own response. Use an **Idea Card** when the reading gives you an idea worth developing. An **Index Card** can collect links to notes for a topic or project. Zotero can help you find and insert a source; you decide how to organize your bibliography and work plan.

Eco's method is especially helpful when you need to distinguish **what a source says** from **what you think about it**, and when you want to return to the exact page later. Cardify supplies tools for this kind of work; it does not automatically build Eco's complete research system for you.

### Niklas Luhmann: develop connected lines of thought

Luhmann's physical card index used fixed addresses, sequences, branches, cross-references, and an index of entry points. New notes could be placed near an existing line of thought without renumbering the whole collection. Cross-references could connect ideas in different places, allowing several paths through the file.

**Try it in Cardify:** choose the **Luhmann** ID style, write an idea, and save it. Use **Continue sequence** for the next address in a sequence or **Branch from card** for an offshoot. Add links and a sentence explaining why the notes belong together. An Index Card can serve as an entry point into a topic.

Cardify's numbering is **Luhmann-inspired**, not an exact reconstruction of every address in his historical archive. You remain free to edit an ID or write notes in a different style.

### Obsidian: work with connected Markdown files

Obsidian is an app for working with a vault of files; it is not a single prescribed research method. Its internal links let you connect notes digitally using `[[wiki links]]`. You can use an Eco-inspired research practice, a Luhmann-inspired slip box, or your own approach in Obsidian.

**Try them together:** select an Obsidian vault as your notes folder and save cards into it. Cardify creates ordinary Markdown files, and its note picker inserts links to existing filenames. Open the same vault in Obsidian to continue working there; print the cards you want in your physical box. Cardify does not provide a separate sync service, and the paper copy will not update itself when a Markdown file changes. Reprint a card when you want the paper copy to reflect edits.

## Continue a sequence or branch from a card?

Think of a **continuation** as the next address at the same level and a **branch** as a new address extending from the current one. These are filing relationships; you choose what the relationship means in your writing.

| Current card | Action | Example new ID | A possible use |
| --- | --- | --- | --- |
| `1a` | Continue sequence | `1b` | Add the next note in a line of thought. |
| `1a` | Branch from card | `1a1` | Develop an offshoot or a more specific question. |
| `1a1` | Continue sequence | `1a2` | Add another note at the offshoot's level. |
| `1a1` | Branch from card | `1a1a` | Explore another offshoot. |

These examples assume the suggested IDs are available. Cardify searches for existing IDs and skips ones already in use. Your actual suggestion may differ, and you can edit it. **Continue sequence** appears in Luhmann mode; **Branch from card** is available in Luhmann and Timestamp modes.

To use either action:

1. Give the current card an ID. If the card is new or has unsaved edits, Cardify asks you to save it first.
2. Choose **Continue sequence** or **Branch from card**. Cardify creates a new draft with a suggested ID and a link back to the saved card.
3. Give the new draft a title, write your note, and save it. The new draft is **not saved automatically**.

The original card keeps its ID and filename. Cardify does not automatically add a link from the original card to the new one; add one yourself if you want a link in both directions. Neither action automatically renumbers existing notes.

## Choose an ID style

The **ID style** selector sits above the writing area. IDs are optional and editable; when present, they appear in small type on the top line of the printed card and as `card_id` in the Markdown frontmatter. The first line wraps before it reaches the ID; an unusually long ID uses its own line.

| Style | What Cardify suggests | Useful when |
| --- | --- | --- |
| **Timestamp** | A local date-and-time ID, such as `202611122145`. If needed, a suffix distinguishes collisions. | You want a chronological identifier and simple filenames. |
| **Luhmann** | An available numeric starting ID, with continuation and branch suggestions. | You want addresses that express sequences and offshoots. |
| **Title only** | No new ID. | You prefer a descriptive filename without an automatically generated ID. |

With Timestamp or Luhmann selected, a new note's suggested filename combines its ID and title. For example, a card titled `Ways of remembering` might be suggested as `202611122145 Ways of remembering.md`. Title only suggests a title-based filename. If an unsaved Research card already has an ID when you choose Luhmann, Cardify checks the notes or save folder and shows the current and suggested IDs. Choose **Replace ID** to use the new one, or **Keep Current ID** to leave the ID and style unchanged. Saved card IDs and filenames are not changed automatically, and Debate cards keep their own IDs. You can also edit the ID field yourself.

Before saving an ID-bearing note, Cardify checks the selected notes folder and the destination folder, including their subfolders, for duplicate IDs it recognizes. If the check cannot be completed, Cardify stops the save instead of assuming the ID is unique. These checks apply only to the folders searched and cannot prevent simultaneous changes by another app.

## Link and format notes

In a Markdown card, type `[[` to search the selected notes folder by filename and insert a link. Use the arrow keys to choose a suggestion, Return or Tab to insert it, and Escape to dismiss the list. You can also click **Link Note** and search for a note. Cardify inserts a path-based link such as `[[Research/Memory and archives]]`; it does not change the linked file.

To follow a link, **Command-click** it in the Markdown editor, or click the underlined link in the card preview. `[[Note]]`, `[[Folder/Note|label]]`, and heading links such as `[[Note#Heading]]` open Markdown cards in Cardify; web links open in your browser. Links to Zotero items open in Zotero. Cardify asks about unsaved changes before opening another card.

Choose the vault root with **File → Choose Notes Folder…** so note links resolve against your vault. If a filename is ambiguous or a target cannot be found, Cardify tells you instead of opening a different note. Heading links support Markdown headings; Obsidian block links are not supported yet. Preview links are interactive only inside Cardify; Cardify does not add its internal link actions to exported or printed PDFs. The Zotero open-source line is hidden in the printed preview, but you can Command-click it in the editor.

Add a few words explaining a link when they will help you later, for example:

```md
Related: [[Research/Memory and archives]] — connects this idea to how archives preserve context.
```

Use the buttons above the editor for **bold**, *italic*, headings, bullet lists, and tasks. Markdown and wiki-link labels appear in the card preview and print output. Cardify renders a subset of Markdown; it does not promise every Obsidian or Markdown feature will print exactly as it appears in another app.

## Add a Zotero source

1. Open Zotero. In Zotero, enable **Settings → Advanced → Allow other applications on this computer to communicate with Zotero**.
2. In a Markdown card, click **Add Zotero Source**.
3. Search your library, select a source, and optionally enter a page or other location. Cardify adds a readable source and a link that opens the item in Zotero.

You can choose your personal library or an available group, search more fields, and load additional results. Zotero must be running with local access enabled. Cardify reads through Zotero's local API and does not modify your library. Check source details and page numbers before citing them.

## Weekly habit cards

Choose **Habit** or **Templates → Weekly Habit Tracker**. Edit the heading, add a row for each habit, and click the weekday boxes to add or remove an X. You can also leave the boxes empty and mark the printed card by hand.

Use the preview's **Text size** control to change the tracker font. Seven standard rows fit on a landscape card at the default size; larger text, long habit names, or more rows can continue onto additional cards. Saving produces a Markdown table. Opening a table saved by Cardify restores it in the habit editor.

## To-do cards

Choose **To Do** to write a heading and add tasks. Click each checkbox to mark or clear it, and use **Add task** or the minus button to change the list. Adjust text size and orientation beside the preview, then save, print, or both.

The saved file uses ordinary Markdown task checkboxes and a `<!-- cardify:todo -->` marker. The marker is hidden on the printed card and lets Cardify reopen the list in the structured editor. If a marked file contains additional content the editor cannot safely represent, Cardify opens it as a Research note instead of discarding that content.

## Debate: resolutions and argument maps

Choose **Debate** to organize arguments using the same Markdown draft, ID options, links, Zotero tools, preview, and print controls as Research. The argument map shows a resolution at the top, AFF and DEF points underneath, and each point's evidence, objections, arguments, and replies below it. This structure is inspired by [William Lane Craig's description of preparing and reusing documented argument and response briefs](https://www.reasonablefaith.org/media/reasonable-faith-podcast/dr-craig-live-at-west-university-baptist-church-part-1/); the visual map is Cardify's own design.

1. Choose **File → Choose Notes Folder…** and select your notes folder. The argument map searches this folder; if none is selected, it uses the save folder.
2. Under **New**, choose **Resolution**, give the resolution a title, and save it in the notes folder. Existing debate projects still appear as resolutions. Use **Mark as** to identify an existing draft without renaming its file.
3. Open **Argument map**. The map guides you to create a resolution, then add an AFF point; you can also add as many DEF points as you need. New points receive IDs such as `AFF-01` and `DEF-01`, shown at the top right of their cards and in their suggested filenames. Existing IDs and filenames are kept. Choose a notes or save folder first so Cardify can check for duplicate IDs.
4. Select a point or connected card on the map. Choose **Add objection or counterargument**, **Add supporting evidence**, **Add response**, or **Add supporting argument**. The new card branches from the selected card, which becomes its primary parent. You can select that new card later to continue the chain. It inherits its parent's ID: an objection under `AFF-01` might be `AFF-01-OB-01`, and its reply `AFF-01-OB-01-RE-01`. The other type codes are `EV` (evidence), `AR` (argument), and `NT` (other note); each type has its own sequence. If an older parent has no ID, you can add one first or continue without an inherited ID. Save and refresh the map to see each new card.
5. To connect an existing draft to another card, select its parent on the map and choose **Set as primary parent**. To connect it elsewhere too, choose **Add related parent**. A card has one primary parent; dashed connections show additional related parents. You can add a brief explanation of each relationship. Cardify refuses primary links that would make a cycle.

Select any node to inspect its actions; double-click it or choose **Open card** to edit the note. Choose **Focus branch** above the map, or **Focus on this branch** beside the selected card, to see its path and immediate children. Select another card to follow the chain, or choose **Full map** to return to the whole debate. Related cards are cross-links, not additional primary parents. Use the resolution picker to switch between debates and search within the displayed map. The **Unassigned** view keeps earlier AFF/DEF notes that have no resolution link accessible. A parent may belong to more than one resolution, and a related card may appear under multiple points without being copied.

Each primary connection can be marked **Supports parent**, **Challenges parent**, or **Not specified**. The relation describes the connection, not the card type: supporting evidence supports its selected parent, while an objection challenges it. A new response starts unspecified; open the card and use **Relationship to parent** to choose. Older cards remain unspecified until you choose, and changing a card's primary parent clears the old connection's label. Save the card after changing its relationship.

Resolutions, points, and connected cards are ordinary Markdown files. Role and relationship markers are hidden from the printed card, and parent relationships are readable wiki links. No linked note is copied, automatically renamed, or modified when you connect your current draft. If a linked file is moved or renamed outside Cardify, repair its link in the Markdown. Anki integration and study scheduling are not included in this version.

## Printing

1. Choose **Landscape · 5 × 3** or **Portrait · 3 × 5** beside the preview.
2. Review the preview and card count. Adjust text size if needed; long content can continue onto additional cards.
3. Click **Print**. In your printer dialog, choose a printer-supported **3 × 5-inch** paper size and the matching orientation. Print at **100% scale**, without fit-to-page scaling.
4. Feed the cards according to your printer's instructions. Print a test card to check the feed, orientation, ink, and margins for your printer.

Cardify generates a 3 × 5-inch PDF with a 3/8-inch inset. Actual printable margins and media handling depend on the printer and driver. If the result is clipped, blank, or misaligned, check the paper size, media type, tray, and scaling in the printer dialog; try **File → Export PDF…** to inspect or print the PDF separately. A correct preview cannot guarantee that a particular printer will handle the card stock correctly.

For a light background, enable **Dot grid on cards** under **Settings → Appearance**. It appears in the preview, exported PDF, and printed cards.

## Clip research from the web

The optional browser clipper sends selected webpage text, the page title, and URL to Cardify for review. Open Cardify once before using it so macOS can register the app's link handler.

- **Chrome:** load [Extensions/Chrome](Extensions/Chrome) with **Load unpacked** at `chrome://extensions`, after enabling Developer mode.
- **LibreWolf:** [Download the clipper XPI](Downloads/Cardify-Clipper-LibreWolf.xpi). In `about:addons`, use the gear menu → **Install Add-on From File…**. This package is unsigned. LibreWolf must support unsigned extensions and have signature verification disabled before it can install it; that setting affects all extensions in the profile. Once installed, it persists across restarts. This package does not currently update itself.
- **Firefox:** the XPI is not Mozilla-signed and cannot be permanently installed in ordinary Firefox release builds. For testing, load [Extensions/LibreWolf](Extensions/LibreWolf) from `about:debugging` → **This Firefox** → **Load Temporary Add-on**. A Mozilla-signed release is not yet available.

Select text on a supported webpage, open the extension, and choose **Open in Cardify**. Review the header, note, and source before appending to or replacing your draft. Some browser pages, embedded frames, and PDF viewers restrict access; images and video are not extracted, and very long selections are rejected. Browser-to-app handoff has not been tested across every browser and macOS version.

## Privacy and your files

Drafts and the default save-folder setting are stored locally. Markdown files are saved where you choose. The clipper passes selected text, title, and the full URL through a local custom URL scheme; it does not send them to a remote Cardify service. Other local software or system components may see a custom URL, and a webpage URL can contain private query parameters. Review a source before sharing or printing it. Zotero integration communicates with the local Zotero service.

## Build from source

On macOS, install the Apple Command Line Tools, then run:

```sh
./scripts/build.sh
open build/Cardify.app
```

The script builds a universal app targeting macOS 13 and later and signs it ad hoc. The result is not notarized. Run `./scripts/test.sh` for library, graph physics, index, workflow, appearance, to-do, history, and draft-protection checks, `./scripts/test-printed-id.sh` for PDF layout checks, `./scripts/test-preview-links.sh` for clickable-preview checks, `./scripts/test-preview-stability.sh` for preview updates, `./scripts/test-todo-pdf.sh` for to-do printing, `./scripts/test-graph-layout.sh` for graph layout, and `./scripts/test-graph-open.sh` for graph-opening safeguards.

## Further reading

- Johannes F. K. Schmidt, [“Niklas Luhmann's Card Index: The Fabrication of Serendipity”](https://www.uni-bielefeld.de/fakultaeten/soziologie/forschung/luhmann-archiv/pdf/jschmidt_niklas-luhmanns-card-index_-sociologica_2018_12-1.pdf) and the [Niklas Luhmann Archive's overview](https://niklas-luhmann-archiv.de/nachlass/zettelkasten).
- Umberto Eco, [*How to Write a Thesis*](https://mitpress.mit.edu/9780262527132/how-to-write-a-thesis/), especially its chapters on bibliography, index cards, and the work plan.
- Obsidian Help, [Internal links](https://obsidian.md/help/links).

## License

Cardify is open source under the [MIT License](LICENSE).

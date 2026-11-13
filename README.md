# Cardify

**Write a note once. Keep it as Markdown, print it on 3 × 5-inch index cards, or do both.**

Cardify is a free, open-source Mac app for research, reading, studying, and keeping a paper-and-digital slip box. Write in Markdown, connect your notes, add Zotero sources, and see how your cards will print as you work. You can use Cardify with an Obsidian vault, a folder of Markdown files, a physical card box, or any combination of the three.

[Download Cardify for Mac](https://github.com/wilbursalazar/Cardify/raw/refs/heads/main/Downloads/Cardify-Mac.zip) · [Get started](#your-first-card) · [Choose a note-taking approach](#three-approaches-one-flexible-workflow) · [Printing help](#printing)

## Download and open

1. [Download Cardify-Mac.zip](https://github.com/wilbursalazar/Cardify/raw/refs/heads/main/Downloads/Cardify-Mac.zip) and unzip it.
2. Move **Cardify.app** to Applications if you like, then open it.
3. If macOS blocks the app, look in **System Settings → Privacy & Security** for an option to allow it to open.

Cardify requires **macOS 13 or later** and includes code for both Apple silicon and Intel Macs. The current build is ad-hoc signed and **not Apple-notarized**, so macOS may ask for confirmation. Compatibility across all Macs and printers has not been tested. Cardify is currently a Mac app; Windows and Linux versions are not available.

## Your first card

1. Open Cardify. Choose **Markdown** to write a note, or **Habits** for a weekly tracker.
2. Optional: choose **File → Choose Save Folder…** to set the folder offered when you save a new note or export a PDF. To work with an Obsidian vault, you can choose a folder inside your vault.
3. Optional: choose **File → Choose Notes Folder…** and select your vault or notes folder. For Obsidian, select the vault root so inserted paths are relative to the vault. Cardify searches this folder for notes to link and for existing card IDs. It can be the same folder as your save folder.
4. Enter a title and write, or choose **Templates → Idea Card**, **Reading Card**, or **Index Card**. Templates insert editable Markdown at the cursor; they do not replace your draft.
5. Check the preview. Use the controls beside it to change orientation, text size, or the dot grid. Then choose **Save…**, **Print…**, or **Save & Print…**.

**Save** opens a dialog to save a `.md` file. **Print** opens the printer dialog. **Save & Print** saves first and starts printing only if the save succeeds. **File → Export PDF…** saves a PDF for review or printing later. Longer notes can continue onto more than one card.

> Save folder and notes folder have different jobs: the first is a default destination; the second is the collection Cardify searches. If no notes folder is selected, note suggestions fall back to the save folder. Saving still lets you choose a destination.

## Three approaches, one flexible workflow

You do not have to follow a single system. These approaches answer different questions, and Cardify lets you borrow the parts you find useful.

### Umberto Eco: keep track of your research

In *How to Write a Thesis*, Umberto Eco describes using different files of cards to organize research. A **bibliography file** records works to find or consult; a **reading file** records works actually read, with summaries, quotations, assessments, and the details needed to find the source again. He also discusses cards for ideas and quotations. A working plan helps relate material to a piece of writing.

**Try it in Cardify:** choose a **Reading Card**, record a summary or clearly marked quotation, add the source and page, and write your own response. Use an **Idea Card** when the reading gives you an idea worth developing. An **Index Card** can collect links to notes for a topic or project. Zotero can help you find and insert a source; you decide how to organize your bibliography and work plan.

Eco's method is especially helpful when you need to distinguish **what a source says** from **what you think about it**, and when you want to return to the exact page later. Cardify supplies tools for this kind of work; it does not automatically build Eco's complete research system for you.

### Niklas Luhmann: develop connected lines of thought

Luhmann's physical card index used fixed addresses, sequences, branches, cross-references, and an index of entry points. New notes could be placed near an existing line of thought without renumbering the whole collection. Cross-references could connect ideas in different places, allowing several paths through the file.

**Try it in Cardify:** choose the **Luhmann** ID style, write an idea, and save it. Use **Continue sequence…** for the next address in a sequence or **Branch from card…** for an offshoot. Add links and a sentence explaining why the notes belong together. An Index Card can serve as an entry point into a topic.

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

These examples assume the suggested IDs are available. Cardify searches for existing IDs and skips ones already in use. Your actual suggestion may differ, and you can edit it. **Continue sequence…** appears in Luhmann mode; **Branch from card…** is available in Luhmann and Timestamp modes.

To use either action:

1. Give the current card an ID. If the card is new or has unsaved edits, Cardify asks you to save it first.
2. Choose **Continue sequence…** or **Branch from card…**. Cardify creates a new draft with a suggested ID and a link back to the saved card.
3. Give the new draft a title, write your note, and save it. The new draft is **not saved automatically**.

The original card keeps its ID and filename. Cardify does not automatically add a link from the original card to the new one; add one yourself if you want a link in both directions. Neither action automatically renumbers existing notes.

## Choose an ID style

The **ID style** selector sits above the writing area. IDs are optional and editable; when present, they appear in small type on the printed card and as `card_id` in the Markdown frontmatter.

| Style | What Cardify suggests | Useful when |
| --- | --- | --- |
| **Timestamp** | A local date-and-time ID, such as `202611122145`. If needed, a suffix distinguishes collisions. | You want a chronological identifier and simple filenames. |
| **Luhmann** | An available numeric starting ID, with continuation and branch suggestions. | You want addresses that express sequences and offshoots. |
| **Title only** | No new ID. | You prefer a descriptive filename without an automatically generated ID. |

With Timestamp or Luhmann selected, a new note's suggested filename combines its ID and title. For example, a card titled `Ways of remembering` might be suggested as `202611122145 Ways of remembering.md`. Title only suggests a title-based filename. Switching styles does not remove an existing ID or automatically rename an existing file; you can edit the ID field yourself.

Before saving an ID-bearing note, Cardify checks the selected notes folder and the destination folder, including their subfolders, for duplicate IDs it recognizes. If the check cannot be completed, Cardify stops the save instead of assuming the ID is unique. These checks apply only to the folders searched and cannot prevent simultaneous changes by another app.

## Link and format notes

In a Markdown card, type `[[` to search the selected notes folder by filename and insert a link. Use the arrow keys to choose a suggestion, Return or Tab to insert it, and Escape to dismiss the list. You can also click **Link Note…** and search for a note. Cardify inserts a path-based link such as `[[Research/Memory and archives]]`; it does not change the linked file.

Add a few words explaining a link when they will help you later, for example:

```md
Related: [[Research/Memory and archives]] — connects this idea to how archives preserve context.
```

Use the buttons above the editor for **bold**, *italic*, headings, bullet lists, and tasks. Markdown and wiki-link labels appear in the card preview and print output. Cardify renders a subset of Markdown; it does not promise every Obsidian or Markdown feature will print exactly as it appears in another app.

## Add a Zotero source

1. Open Zotero. In Zotero, enable **Settings → Advanced → Allow other applications on this computer to communicate with Zotero**.
2. In a Markdown card, click **Add Zotero Source…**.
3. Search your library, select a source, and optionally enter a page or other location. Cardify adds a readable source and a link that opens the item in Zotero.

You can choose your personal library or an available group, search more fields, and load additional results. Zotero must be running with local access enabled. Cardify reads through Zotero's local API and does not modify your library. Check source details and page numbers before citing them.

## Weekly habit cards

Choose **Habits** or **Templates → Weekly Habit Tracker**. Edit the heading, add a row for each habit, and click the weekday boxes to add or remove an X. You can also leave the boxes empty and mark the printed card by hand.

Use the preview's **Text size** control to change the tracker font. Seven standard rows fit on a landscape card at the default size; larger text, long habit names, or more rows can continue onto additional cards. Saving produces a Markdown table. Opening a table saved by Cardify restores it in the habit editor.

## Printing

1. Choose **Landscape · 5 × 3** or **Portrait · 3 × 5** beside the preview.
2. Review the preview and card count. Adjust text size if needed; long content can continue onto additional cards.
3. Click **Print…**. In your printer dialog, choose a printer-supported **3 × 5-inch** paper size and the matching orientation. Print at **100% scale**, without fit-to-page scaling.
4. Feed the cards according to your printer's instructions. Print a test card to check the feed, orientation, ink, and margins for your printer.

Cardify generates a 3 × 5-inch PDF with a 3/8-inch inset. Actual printable margins and media handling depend on the printer and driver. If the result is clipped, blank, or misaligned, check the paper size, media type, tray, and scaling in the printer dialog; try **File → Export PDF…** to inspect or print the PDF separately. A correct preview cannot guarantee that a particular printer will handle the card stock correctly.

For a light background, choose **Design → Dot grid** beside the preview. It appears in the preview, exported PDF, and printed cards.

## Clip research from the web

The optional browser clipper sends selected webpage text, the page title, and URL to Cardify for review. Open Cardify once before using it so macOS can register the app's link handler.

- **Chrome:** load [Extensions/Chrome](Extensions/Chrome) with **Load unpacked** at `chrome://extensions`, after enabling Developer mode.
- **LibreWolf / Firefox:** load [Extensions/LibreWolf](Extensions/LibreWolf) through `about:debugging` → **This Firefox** → **Load Temporary Add-on**, selecting `manifest.json`. This is a **temporary** installation and is removed when the browser restarts; a permanently signed add-on is not currently provided.

Select text on a supported webpage, open the extension, and choose **Open in Cardify**. Review the header, note, and source before appending to or replacing your draft. Some browser pages, embedded frames, and PDF viewers restrict access; images and video are not extracted, and very long selections are rejected. Browser-to-app handoff has not been tested across every browser and macOS version.

## Privacy and your files

Drafts and the default save-folder setting are stored locally. Markdown files are saved where you choose. The clipper passes selected text, title, and the full URL through a local custom URL scheme; it does not send them to a remote Cardify service. Other local software or system components may see a custom URL, and a webpage URL can contain private query parameters. Review a source before sharing or printing it. Zotero integration communicates with the local Zotero service.

## Build from source

On macOS, install the Apple Command Line Tools, then run:

```sh
./scripts/build.sh
open build/Cardify.app
```

The script builds a universal app targeting macOS 13 and later and signs it ad hoc. The result is not notarized.

## Further reading

- Johannes F. K. Schmidt, [“Niklas Luhmann's Card Index: The Fabrication of Serendipity”](https://www.uni-bielefeld.de/fakultaeten/soziologie/forschung/luhmann-archiv/pdf/jschmidt_niklas-luhmanns-card-index_-sociologica_2018_12-1.pdf) and the [Niklas Luhmann Archive's overview](https://niklas-luhmann-archiv.de/nachlass/zettelkasten).
- Umberto Eco, [*How to Write a Thesis*](https://mitpress.mit.edu/9780262527132/how-to-write-a-thesis/), especially its chapters on bibliography, index cards, and the work plan.
- Obsidian Help, [Internal links](https://obsidian.md/help/links).

## License

Cardify is open source under the [MIT License](LICENSE).

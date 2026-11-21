# Kaster

**An offline, digital-and-physical slip box. Capture an idea, connect it, and print it as a perfect 3 × 5-inch index card.**

Kaster is a free, open-source Mac app that does one thing: it turns research into a permanent, interconnected system of index cards that live both on your Mac and in a box on your desk. Cards are plain Markdown files you own. Kaster gives them numbers, links and a typeset look, and prints them exactly to size.

[Download Kaster for Mac](https://github.com/wilbursalazar/Cardify/raw/refs/heads/main/Downloads/Kaster-Mac.zip) · [Philosophy](#philosophy) · [Card types](#card-types) · [Features](#features) · [Printing](#printing) · [Build from source](#build-from-source)

## Philosophy

Kaster deliberately isn't a general writing app, a project manager or another note database. It aims to be the best possible tool for the slip-box method, judged by three activities:

- **Capture:** get an idea or a source onto a card in seconds.
- **Connect:** link the card to what you already think, and let lines of thought branch.
- **Preserve:** keep every card findable and printable, so the digital box and the physical box stay in step.

A few commitments follow from that:

- **Plain Markdown is the source of truth.** Every card is an ordinary `.md` file, readable in any editor and compatible with Obsidian. Nothing is locked in a database.
- **Offline first.** Everything, including typesetting, runs on your Mac. Nothing is uploaded.
- **The card is the unit.** One idea per card, small enough for 3 × 5 inches. If a card overflows, it probably holds two ideas.
- **Print is a core feature.** A card prints as a faithful physical card, with exact margins and typography, in pure black ink unless you choose color.
- **Frictionless and reversible.** Cards save themselves, links repair themselves when files move or are renamed, and nothing is silently lost.

The design draws on Niklas Luhmann's numbered, branching card file; Umberto Eco's reading cards from *How to Write a Thesis*; and the habit of sorting themed notecards into a box to build a book.

## Card types

| Type | What it's for | Saved as |
| --- | --- | --- |
| **Research** | What a source says (quotation or paraphrase) and your response, with `Source: [[Bibliography card]], p. 42`. Eco-style. | `Research/Title.md` |
| **Zettel** | One permanent idea, with a Luhmann address such as `21/1a`. | `Zettel/21-1a-Title.md` |
| **Quick** | Just a title: capture now, develop later. Promote it to a Zettel or Research card with one click. | `Quick/Title.md` |
| **Bibliography** | One card per source: title, author, year. It shows which Research cards cite it. | `Bibliography/Title.md` |

**Luhmann numbering**
- New top-level cards are numbered 1, 2, 3…
- **Continue** adds the next card at the same level: 21 → 22, 21/1 → 21/2, 21/1a → 21/1b.
- **Branch** goes one level deeper: 21 → 21/1, 21/1 → 21/1a, 21/1a → 21/1a1.
- Because a card's number never changes, a new thought can be filed right behind the card it develops.

**Themes** (optional, in Settings): each card's first `#tag` becomes its theme. It prints in the card's top corner, and a Themes list in the sidebar gathers, orders and prints a theme's cards as a stack, like a box of themed dividers.

**Artifacts:** habit trackers, to-do lists and debate maps are still available from the Artifacts menu. They're kept apart from the slip box, in folders you choose.

## Features

### Capture
- **⌘N** makes a new card of the type you used last. The cursor lands on the title.
- **No Save dialog:** a card saves itself into its folder as soon as it has a title, and keeps autosaving.
- **Changing a title renames the file** and updates every link to it across the vault.
- **Zotero:** add a source from your local Zotero library, from the toolbar or the selection bar.
- **Web clipper (optional):** send selected text, the page title and the URL from Chrome or LibreWolf.

### Connect
- Type `[[` to link a card. ⌘-click a link to open it.
- **⌘-click a link to a card that doesn't exist yet** and Kaster creates it as a Quick card.
- **Backlinks and Info:** the inspector shows what links here, what this card links to, and the card's details.
- **Open Beside:** edit a second card next to the first; both stay editable.
- **Graph:** see connections in a separate window.
- **Index cards:** entry points into a subject that can point to cards anywhere in the box.
- Every card gets a permanent hidden `uid`, so its identity survives renumbering and renaming.

### Write
- **Live mode:** headings, emphasis, links and tags are styled while you type. Markdown symbols hide except on the line you're editing. **Source mode** shows plain Markdown.
- **Selection toolbar:** bold, italic, highlight, H1–H3, bullets, code, `[[link]]`, math and Zotero.
- **Math and tables:** write math in `$…$` / `$$…$$` and tables with `| pipes |`. With the Typst engine, math can use Typst syntax (`frac(a, b)`) or LaTeX commands (`\frac{a}{b}`).

### Organize and find
- **Library:** All Cards, Recent, Favorites, Unprinted, Graph, Search (⌘F), Themes and your folders.
- **Note list:** each card shows its type, its ID and when it last changed. Sort by date, ID, title, or **Manual**: drag cards to reorder them (saved as `order:` in the card).
- **Folders:**
  - Drag cards and folders between folders; links are kept intact.
  - Right-click for New Card Here, New Folder Here, Move to…, Rename, Duplicate and Trash.
  - Resize the two left panes by dragging.
- **Organize Vault into Kaster Folders** (File menu): sorts an existing folder of notes into the card-type folders. It shows every move first, makes a zip backup, and repairs links.

## Printing

Kaster typesets cards with [Typst](https://typst.app), bundled inside the app, so the preview is exactly what prints. A LaTeX engine (Pandoc + XeLaTeX from your own TeX installation) is available in Settings.

- **3 × 5 in cards**, landscape or portrait, ⅜ in margins, at the text size you pick. Print at 100% scale.
- **Black only (default):** text, tables, rules and IDs print in pure black ink (K-only), and images in grayscale. **Color:** black text, purple links and color images.
- **Save & Print**, **⌘P**, or the PDF button, which saves `Card.pdf` next to `Card.md`.
- **Batch printing:**
  - selected cards (⌘-click)
  - the current list
  - a whole folder
  - a Zettel and its entire branch, in sequence order
  - every card changed since your last print (the **Unprinted** list)
- Long cards continue onto additional cards automatically.

## Download and open

1. [Download Kaster-Mac.zip](https://github.com/wilbursalazar/Cardify/raw/refs/heads/main/Downloads/Kaster-Mac.zip) and unzip it.
2. Move **Kaster.app** to Applications, then open it. The first time, Kaster creates your slip box at `~/Documents/Kaster`. Choose another folder with **File → Choose Notes Folder…**.
3. If macOS blocks the app, look in **System Settings → Privacy & Security** for an option to allow it to open.

Kaster requires **macOS 13 or later**. The app is ad-hoc signed and **not Apple-notarized**, so macOS may ask for confirmation. The bundled Typst engine is for Apple silicon; on Intel Macs, Kaster uses an installed `typst` if one is present, or a basic built-in renderer otherwise.

## Appearance

Kaster has six appearances: System, Light, Dark, Charcoal, Slate, and **Midnight**, a high-contrast dark theme that eases from near-black into a faint violet. Settings also has the dot-grid option for printed cards, the typesetting engine, Themes, and the folders used for artifacts.

## Clip research from the web

The optional browser clipper sends selected webpage text, the page title and the URL to Kaster for review. Open Kaster once before using it, so macOS can register the app's link handler.

- **Chrome:** at `chrome://extensions`, enable Developer mode, then load [Extensions/Chrome](Extensions/Chrome) with **Load unpacked**.
- **LibreWolf:** [download the clipper XPI](Downloads/Cardify-Clipper-LibreWolf.xpi), then in `about:addons` use the gear menu → **Install Add-on From File…**. The package is unsigned, so LibreWolf must allow unsigned extensions.
- **Firefox:** for testing, load [Extensions/LibreWolf](Extensions/LibreWolf) from `about:debugging` → **This Firefox** → **Load Temporary Add-on**.

## Privacy and your files

Your cards are Markdown files in the folder you choose. Drafts and settings stay on your Mac. Typesetting runs locally, and nothing is sent to a remote Kaster service. The clipper passes the selected text, title and URL through a local URL scheme.

## Build from source

Install the Apple Command Line Tools and [Typst](https://typst.app) (`brew install typst`), then run:

```sh
./scripts/build.sh
open build/Kaster.app
```

The script builds a universal app for macOS 13 and later, bundles Typst and its Markdown and math packages (licenses in `Resources/Typst/NOTICE.md`), and signs the app ad hoc.

The code is in two parts. `Sources/Core` is everything that isn't screen code: cards and the vault, saving, card changes, IDs, links, the library index, the keyword register and Zotero. It never imports SwiftUI. `Sources/App` holds the windows and views, and `Sources/Main.swift` is the entry point.

Run `./scripts/test.sh` for the test suite (`./scripts/test.sh Vault Zotero` runs just those). It compiles Core, and Core plus App, once as testable libraries, then builds and runs each folder in `Tests/` against the one it imports. That proves Core builds without the app. GitHub runs the build and the suite on every push.

## Further reading

- Johannes F. K. Schmidt, ["Niklas Luhmann's Card Index: The Fabrication of Serendipity"](https://www.uni-bielefeld.de/fakultaeten/soziologie/forschung/luhmann-archiv/pdf/jschmidt_niklas-luhmanns-card-index_-sociologica_2018_12-1.pdf), and the [Niklas Luhmann Archive](https://niklas-luhmann-archiv.de/nachlass/zettelkasten).
- Umberto Eco, [*How to Write a Thesis*](https://mitpress.mit.edu/9780262527132/how-to-write-a-thesis/), especially the chapters on index cards and the work plan.
- Sönke Ahrens, *How to Take Smart Notes*.

## License

Kaster is open source under the [MIT License](LICENSE).

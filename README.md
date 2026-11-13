# Cardify

Cardify is a free, open-source Mac app for writing Markdown notes and printing them on 3 × 5-inch index cards. It includes a research-card template, a weekly paper habit tracker, a Zotero source picker, and optional browser clippers.

## Build

On macOS with the Apple Command Line Tools installed, run:

```sh
./scripts/build.sh
open build/Cardify.app
```

The app is ad-hoc signed, not notarized. macOS may require an explicit confirmation before opening it. This build script targets the Mac on which it is run; support for other macOS releases and hardware has not been comprehensively tested.

## Print

Choose a printer-supported 3 × 5-inch paper size and matching orientation in the print dialog; print at 100% scale. The generated PDF uses a 3/8-inch inset and continues long notes onto additional cards. Printer feed, available media sizes and nonprintable margins vary; verify using a test card. Export PDF is available for checking first.

## Research clipper

The `Extensions/Chrome` folder can be loaded with Chrome's **Load unpacked** option at `chrome://extensions` after enabling Developer mode. The `Extensions/LibreWolf` folder can be loaded temporarily from `about:debugging` → **This Firefox** → **Load Temporary Add-on**; select its `manifest.json`. Temporary Firefox-family add-ons are removed when the browser restarts. Open Cardify once before using the clipper so macOS can register its URL scheme.

Select text on a normal webpage, click the extension, then **Open in Cardify**. Review the header, note and source before appending it to or replacing the draft. Browser restrictions prevent access to some pages, embedded frames and PDF viewers; the clipper does not extract images or video. Very long selections are rejected. The browser-to-app handoff has not been comprehensively tested across browsers and macOS versions.

## Zotero

Open Zotero and enable **Settings → Advanced → Allow other applications on this computer to communicate with Zotero**. **Add Source** searches the personal library through the local API. It does not modify Zotero; group libraries are not currently searched.

## Privacy

Drafts and the default save-folder setting are stored locally. The clipper uses active-tab permission and passes the selected text, title and full URL to Cardify via a custom local URL scheme; it does not send them to a remote Cardify service. Custom URLs may be visible to local browser, system, or other URL handlers, and webpage URLs may contain private query parameters. Review sources before sharing, saving or printing them. Zotero integration talks to the local Zotero service.

## License

MIT. See [LICENSE](LICENSE).

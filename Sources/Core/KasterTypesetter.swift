import Foundation
import AppKit
import PDFKit

// Kaster typesets cards with Typst (bundled) or, optionally, LaTeX via Pandoc + XeLaTeX.
// Cards stay Markdown on disk: tables are GitHub-style pipes, math is $LaTeX$ / $$LaTeX$$.
enum TypesetEngine: String, CaseIterable, Identifiable {
    case typst, latex
    var id: String { rawValue }
    var title: String { self == .typst ? "Typst (built in)" : "LaTeX (Pandoc + XeLaTeX)" }
    static func stored(_ value: String) -> TypesetEngine { TypesetEngine(rawValue: value) ?? .typst }
}

/// Black only: every mark uses black ink alone (K in CMYK), images in grayscale, links black.
/// Color: black text and tables, purple links, images as they are.
enum PrintColor: String, CaseIterable, Identifiable {
    case black, color
    var id: String { rawValue }
    var title: String { self == .black ? "Black only" : "Color" }
    static func stored(_ value: String) -> PrintColor { PrintColor(rawValue: value) ?? .black }
}

enum TypesetLayout: Equatable {
    case card(portrait: Bool, fontSize: Double, dotGrid: Bool)
    case document(fontSize: Double)
}

struct TypesetCard: Equatable {
    var markdown: String      // Body only: frontmatter removed, wiki links rewritten
    var id: String?
    var images: [String: URL] // name inside the job folder -> source file
    var theme: String? = nil  // Holiday–Greene theme (first #tag) when Themes is on
}

enum TypesetError: LocalizedError, Equatable {
    case engineMissing(String)
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .engineMissing(let message), .failed(let message): return message
        }
    }
}

enum KasterTypesetter {
    static let cmarker = "@preview/cmarker:0.1.10"
    static let mitex = "@preview/mitex:0.2.7"

    // MARK: Locating engines

    static func typstExecutable() -> URL? {
        var candidates: [URL] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("typst/typst") { candidates.append(bundled) }
        candidates += ["/opt/homebrew/bin/typst", "/usr/local/bin/typst", "\(NSHomeDirectory())/.cargo/bin/typst"].map(URL.init(fileURLWithPath:))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func packageDirectory() -> URL? {
        let fm = FileManager.default
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("typst/packages"), fm.fileExists(atPath: bundled.path) { return bundled }
        // Development builds and tests run from the repository checkout: look up from this file.
        var folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<4 {
            folder = folder.deletingLastPathComponent()
            let packages = folder.appendingPathComponent("Resources/Typst/packages")
            if fm.fileExists(atPath: packages.path) { return packages }
        }
        return nil
    }

    static func latexTools() -> (pandoc: URL, texbin: URL)? {
        let fm = FileManager.default
        let pandoc = ["/opt/homebrew/bin/pandoc", "/usr/local/bin/pandoc"].map(URL.init(fileURLWithPath:)).first { fm.isExecutableFile(atPath: $0.path) }
        let texbin = ["/Library/TeX/texbin", "/usr/local/texlive/bin/universal-darwin", "/opt/homebrew/bin"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            .first { fm.isExecutableFile(atPath: $0.appendingPathComponent("xelatex").path) }
        guard let pandoc, let texbin else { return nil }
        return (pandoc, texbin)
    }

    private static var availability: [TypesetEngine: Bool] = [:]
    private static let availabilityLock = NSLock()
    static func isAvailable(_ engine: TypesetEngine) -> Bool {
        availabilityLock.lock(); defer { availabilityLock.unlock() }
        if let known = availability[engine] { return known }
        let value = checkAvailable(engine)
        availability[engine] = value
        return value
    }
    private static func checkAvailable(_ engine: TypesetEngine) -> Bool {
        switch engine {
        case .typst: return typstExecutable() != nil && packageDirectory() != nil
        case .latex: return latexTools() != nil
        }
    }

    // MARK: Preparing Markdown

    /// Converts a stored card into the Markdown the engines read.
    /// `links: true` keeps clickable in-app links (preview); print output shows plain labels.
    /// The first #tag in the card body — its Holiday–Greene theme.
    static func firstTag(in text: String) -> String? {
        let body = stripFrontmatter(text)
        guard let regex = try? NSRegularExpression(pattern: "(?<![\\w#&/])#([A-Za-z][\\w/-]*)"),
              let match = regex.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length)) else { return nil }
        return (body as NSString).substring(with: match.range(at: 1))
    }

    static func prepare(_ text: String, cardURL: URL? = nil, links: Bool, themes: Bool? = nil) -> TypesetCard {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let metadata = CardMetadata.parse(normalized)
        var body = stripFrontmatter(normalized)
        body = body.replacingOccurrences(of: "^\\n+", with: "", options: .regularExpression)
        body = rewriteWikiLinks(body, links: links)
        body = rewriteZoteroLinks(body, links: links)
        body = body.replacingOccurrences(of: "</?u>", with: "", options: .regularExpression)
        body = body.replacingOccurrences(of: "==(?=\\S)([^=\\n]+?)(?<=\\S)==", with: "<mark>$1</mark>", options: .regularExpression)
        var images: [String: URL] = [:]
        body = rewriteImages(body, base: cardURL?.deletingLastPathComponent(), into: &images)
        let id = metadata.id ?? cardURL.flatMap { BranchIDs.luhmannFilenameID(for: $0) ?? BranchIDs.filenameID(for: $0) }
        let showTheme = themes ?? UserDefaults.standard.bool(forKey: "kasterThemes")
        return TypesetCard(markdown: body, id: id, images: images, theme: showTheme ? firstTag(in: normalized) : nil)
    }

    /// Removes a leading YAML block ("---" … "---" or "...").
    static func stripFrontmatter(_ text: String) -> String {
        var source = text
        if source.hasPrefix("\u{FEFF}") { source.removeFirst() }
        guard source.hasPrefix("---\n") else { return text }
        let lines = source.components(separatedBy: "\n")
        for index in 1..<lines.count where lines[index] == "---" || lines[index] == "..." {
            return lines[(index + 1)...].joined(separator: "\n")
        }
        return text
    }

    static func rewriteWikiLinks(_ text: String, links: Bool) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\[\\[([^\\]|#]*)(#[^\\]|]*)?(?:\\|([^\\]]+))?\\]\\]") else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let target = ns.substring(with: match.range(at: 1))
            let fragment = match.range(at: 2).location == NSNotFound ? "" : ns.substring(with: match.range(at: 2))
            // A link shows the card's name, not its folder path ("Zettel/Idea" → "Idea").
            let name = (target as NSString).lastPathComponent.isEmpty ? target : (target as NSString).lastPathComponent
            let label = match.range(at: 3).location == NSNotFound ? name + fragment : ns.substring(with: match.range(at: 3))
            let escaped = label.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            if links, let action = CardPreviewLinks.action(for: .wiki(target + fragment)) {
                result += "[\(escaped)](\(action.absoluteString))"
            } else {
                result += escaped
            }
            last = NSMaxRange(match.range)
        }
        result += ns.substring(from: last)
        return result
    }

    /// Zotero links ([42](zotero://open-pdf/…)) are clickable in the preview and plain text in print.
    static func rewriteZoteroLinks(_ text: String, links: Bool) -> String {
        guard text.contains("](zotero://"),
              let regex = try? NSRegularExpression(pattern: "(?<!!)\\[((?:\\\\.|[^\\]\\\\\\n])*)\\]\\((zotero://[^)\\s]+)\\)") else { return text }
        let ns = text as NSString
        var result = "", last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let label = ns.substring(with: match.range(at: 1))
            if links, let action = CardPreviewLinks.action(for: .url(ns.substring(with: match.range(at: 2)))) {
                result += "[\(label)](\(action.absoluteString))"
            } else {
                result += label
            }
            last = NSMaxRange(match.range)
        }
        return result + ns.substring(from: last)
    }

    // Typst can only read files inside the job folder, so local images are copied in.
    static func rewriteImages(_ text: String, base: URL?, into images: inout [String: URL]) -> String {
        guard let regex = try? NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\((<[^>]+>|[^)\\s]+)\\)") else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let alt = ns.substring(with: match.range(at: 1))
            var source = ns.substring(with: match.range(at: 2))
            if source.hasPrefix("<") { source = String(source.dropFirst().dropLast()) }
            let decoded = source.removingPercentEncoding ?? source
            var file: URL?
            if decoded.hasPrefix("file://") { file = URL(string: source) }
            else if decoded.hasPrefix("/") { file = URL(fileURLWithPath: decoded) }
            else if !decoded.contains("://"), let base { file = base.appendingPathComponent(decoded) }
            if let file, FileManager.default.isReadableFile(atPath: file.path) {
                let name = "img-\(images.count).\(file.pathExtension.isEmpty ? "png" : file.pathExtension.lowercased())"
                images[name] = file
                result += "![\(alt)](\(name))"
            } else {
                result += alt.isEmpty ? "" : "*[\(alt)]*"
            }
            last = NSMaxRange(match.range)
        }
        result += ns.substring(from: last)
        return result
    }

    // MARK: Rendering

    /// Synchronous; call off the main thread for previews.
    static func render(_ cards: [TypesetCard], layout: TypesetLayout, engine: TypesetEngine, color: PrintColor = .black) -> Result<Data, TypesetError> {
        guard !cards.isEmpty else { return .failure(.failed("Nothing to typeset.")) }
        let job = FileManager.default.temporaryDirectory.appendingPathComponent("kaster-typeset-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true) }
        catch { return .failure(.failed("Could not create a temporary folder: \(error.localizedDescription)")) }
        defer { try? FileManager.default.removeItem(at: job) }
        for card in cards {
            for (name, source) in card.images {
                let destination = job.appendingPathComponent(name)
                if color == .black, writeGrayscale(source, to: destination) { continue }
                try? FileManager.default.copyItem(at: source, to: destination)
            }
        }
        switch engine {
        case .typst: return renderTypst(cards, layout: layout, job: job, color: color)
        case .latex: return renderLaTeX(cards, layout: layout, job: job, color: color)
        }
    }

    /// Black-only printing: images are converted to grayscale before typesetting.
    static func writeGrayscale(_ source: URL, to destination: URL) -> Bool {
        guard let image = NSImage(contentsOf: source),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let gray = context.makeImage() else { return false }
        let rep = NSBitmapImageRep(cgImage: gray)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: destination)) != nil
    }

    static func typstSource(cardCount: Int, layout: TypesetLayout, color: PrintColor = .black) -> String {
        let page: String
        let size: Double
        var background = "none"
        switch layout {
        case .card(let portrait, let fontSize, let dotGrid):
            page = portrait ? "width: 3in, height: 5in, margin: 27pt" : "width: 5in, height: 3in, margin: 27pt"
            size = fontSize
            if dotGrid {
                background = "place(top + left, dx: 27pt, dy: 27pt, rect(width: 100% - 54pt, height: 100% - 54pt, stroke: none, fill: tiling(size: (12pt, 12pt), place(dx: 2.55pt, dy: 2.55pt, circle(radius: 0.45pt, fill: cmyk(0%, 0%, 0%, 28%))))))"
            }
        case .document(let fontSize):
            page = "width: 5.5in, height: auto, margin: (x: 0.45in, y: 0.4in)"
            size = fontSize
        }
        var source = """
        #import "\(cmarker)"
        #import "\(mitex)": mitex
        #let ids = json("ids.json")
        // Pure black ink (K only) so printers never mix black, gray or tables from color inks.
        #let ink = cmyk(0%, 0%, 0%, 100%)
        #let kpurple = \(color == .black ? "ink" : "rgb(\"\(UserDefaults.standard.string(forKey: "kasterAccentHex").flatMap { $0.range(of: "^#?[0-9A-Fa-f]{6}$", options: .regularExpression) != nil ? ($0.hasPrefix("#") ? $0 : "#" + $0) : nil } ?? "#6b40c2")\")")
        #let marker = \(color == .black ? "cmyk(0%, 0%, 0%, 18%)" : "rgb(\"#fff3a0\")")
        #set document(title: none)
        #set page(\(page), background: \(background))
        #set text(font: ("Libertinus Serif", "New Computer Modern"), size: \(size)pt, lang: "en", hyphenate: true, fill: ink)
        #set line(stroke: 0.5pt + ink)
        #show highlight: set highlight(fill: marker)
        #set par(leading: 0.55em, spacing: 0.8em, justify: false)
        #show heading: set text(weight: "bold")
        #show heading.where(level: 1): set text(size: 1.3em)
        #show heading.where(level: 2): set text(size: 1.12em)
        #show heading: set block(above: 0.9em, below: 0.55em)
        #show link: it => text(fill: kpurple, underline(offset: 1.5pt, it))
        #set table(stroke: 0.5pt + ink, inset: (x: 4pt, y: 3pt))
        #show table.cell.where(y: 0): set text(weight: "bold")
        #show raw: set text(font: "DejaVu Sans Mono", size: 0.88em)
        #show quote: set text(style: "italic")
        #set list(indent: 0.4em)
        #set enum(indent: 0.4em)
        // Under Typst, $…$ holds Typst math; math written with LaTeX commands (\\frac…) still works.
        #let kmath(block: false, src) = if src.contains("\\\\") { mitex(block: block, src) } else { math.equation(block: block, eval(src, mode: "math")) }
        #let kcard(index) = {
          let meta = ids.at(index)
          let id = meta.at("id", default: none)
          let theme = meta.at("theme", default: none)
          if id != none { place(top + right, dy: -14pt, text(size: 6.5pt, fill: cmyk(0%, 0%, 0%, 85%), id)) }
          if theme != none { place(top + left, dy: -14.5pt, text(size: 7pt, weight: "bold", tracking: 0.06em, fill: ink, upper(theme))) }
          cmarker.render(
            read("card-" + str(index) + ".md"),
            math: kmath,
            smart-punctuation: true,
            set-document-title: false,
            label-prefix: "c" + str(index) + "-",
            task-list-marker: checked => box(baseline: 0.12em, if checked { sym.ballot.cross } else { sym.ballot }),
            html: (u: (attrs, body) => underline(body), mark: (attrs, body) => highlight(fill: marker, body)),
            scope: (image: (source, ..args) => image(source, ..args)),
          )
        }

        """
        for index in 0..<cardCount {
            if index > 0 { source += "#pagebreak()\n" }
            source += "#kcard(\(index))\n"
        }
        return source
    }

    private static func renderTypst(_ cards: [TypesetCard], layout: TypesetLayout, job: URL, color: PrintColor) -> Result<Data, TypesetError> {
        guard let typst = typstExecutable() else { return .failure(.engineMissing("Typst isn't available. Reinstall Kaster or install Typst.")) }
        guard let packages = packageDirectory() else { return .failure(.engineMissing("Kaster's Typst packages are missing. Reinstall Kaster.")) }
        do {
            for (index, card) in cards.enumerated() {
                try card.markdown.write(to: job.appendingPathComponent("card-\(index).md"), atomically: true, encoding: .utf8)
            }
            let ids = try JSONSerialization.data(withJSONObject: cards.map { card -> [String: Any] in
                ["id": card.id.map { $0 as Any } ?? NSNull(), "theme": card.theme.map { $0 as Any } ?? NSNull()]
            })
            try ids.write(to: job.appendingPathComponent("ids.json"))
            try typstSource(cardCount: cards.count, layout: layout, color: color).write(to: job.appendingPathComponent("main.typ"), atomically: true, encoding: .utf8)
        } catch {
            return .failure(.failed("Could not prepare the card: \(error.localizedDescription)"))
        }
        let output = job.appendingPathComponent("out.pdf")
        let result = run(typst, ["compile", "main.typ", output.path, "--root", job.path,
                                 "--package-path", packages.path, "--package-cache-path", packages.path,
                                 // Kaster's fonts are built into Typst; skipping the system font scan is ~3× faster.
                                 "--ignore-system-fonts", "--diagnostic-format", "short"], in: job, environment: [:])
        if let data = try? Data(contentsOf: output), result.status == 0 { return .success(data) }
        return .failure(.failed(cleanTypstMessage(result.output, cardCount: cards.count)))
    }

    static func cleanTypstMessage(_ raw: String, cardCount: Int) -> String {
        let lines = raw.split(separator: "\n").map(String.init).filter { $0.contains("error") }
        guard let first = lines.first else { return raw.isEmpty ? "Typst could not typeset this card." : raw }
        // "card-0.md:3:5: error: unknown variable" → "Line 3: unknown variable"
        if let range = first.range(of: "error: ") {
            let message = String(first[range.upperBound...])
            let location = first.components(separatedBy: ":")
            if location.count > 2, location[0].hasPrefix("card-"), let line = Int(location[1]) {
                return cardCount > 1 ? "\(location[0]) line \(line): \(message)" : "Line \(line): \(message)"
            }
            return message
        }
        return first
    }

    private static func renderLaTeX(_ cards: [TypesetCard], layout: TypesetLayout, job: URL, color: PrintColor) -> Result<Data, TypesetError> {
        guard let tools = latexTools() else {
            return .failure(.engineMissing("LaTeX needs Pandoc and a TeX distribution (MacTeX). Install them or switch to Typst in Settings."))
        }
        var geometry: [String]
        var fontSize: Double
        switch layout {
        case .card(let portrait, let size, _):
            geometry = portrait ? ["paperwidth=3in", "paperheight=5in"] : ["paperwidth=5in", "paperheight=3in"]
            geometry.append("margin=0.375in")
            fontSize = size
        case .document(let size):
            geometry = ["paperwidth=5.5in", "paperheight=8.5in", "margin=0.45in"]
            fontSize = size
        }
        func latexEscape(_ value: String) -> String {
            var out = ""
            for char in value {
                switch char {
                case "\\": out += "\\textbackslash{}"
                case "{", "}", "$", "&", "#", "_", "%": out += "\\\(char)"
                case "~": out += "\\textasciitilde{}"
                case "^": out += "\\textasciicircum{}"
                default: out.append(char)
                }
            }
            return out
        }
        var markdown = ""
        for (index, card) in cards.enumerated() {
            if index > 0 { markdown += "\n\n\\newpage\n\n" }
            if let theme = card.theme {
                markdown += "```{=latex}\n\\noindent\\textbf{\\scriptsize\\MakeUppercase{\(latexEscape(theme))}}\\par\\vspace{-1.6em}\n```\n\n"
            }
            if let id = card.id {
                markdown += "```{=latex}\n\\hfill\\textcolor{black!85}{\\scriptsize \(latexEscape(id))}\\par\\vspace{-0.8em}\n```\n\n"
            }
            markdown += card.markdown
        }
        let header = """
        \\usepackage{anyfontsize}
        \\usepackage{xcolor}
        \\AtBeginDocument{\\fontsize{\(fontSize)}{\(fontSize * 1.25)}\\selectfont}
        \\setlength{\\parskip}{0.45em}
        \\setlength{\\parindent}{0pt}
        """
        do {
            try markdown.write(to: job.appendingPathComponent("cards.md"), atomically: true, encoding: .utf8)
            try header.write(to: job.appendingPathComponent("header.tex"), atomically: true, encoding: .utf8)
        } catch {
            return .failure(.failed("Could not prepare the card: \(error.localizedDescription)"))
        }
        let output = job.appendingPathComponent("out.pdf")
        var args = ["cards.md", "-f", "markdown+tex_math_dollars+pipe_tables+task_lists+raw_html-implicit_figures",
                    "-o", output.path, "--pdf-engine=xelatex", "-H", "header.tex",
                    "-V", "pagestyle=empty", "-V", "colorlinks=true",
                    "-V", "linkcolor=\(color == .black ? "black" : "violet")", "-V", "urlcolor=\(color == .black ? "black" : "violet")",
                    "-V", "documentclass=article"]
        for item in geometry { args += ["-V", "geometry:\(item)"] }
        let path = [tools.texbin.path, tools.pandoc.deletingLastPathComponent().path, "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
        let result = run(tools.pandoc, args, in: job, environment: ["PATH": path], timeout: 60)
        if let data = try? Data(contentsOf: output), result.status == 0 { return .success(data) }
        let message = result.output.split(separator: "\n").first { $0.hasPrefix("!") || $0.lowercased().contains("error") }.map(String.init)
        return .failure(.failed(message ?? "LaTeX could not typeset this card."))
    }

    /// Launches the engine with posix_spawn. Foundation's Process closes every possible file
    /// descriptor before exec, which costs ~70 ms per launch; POSIX_SPAWN_CLOEXEC_DEFAULT does
    /// the same job in microseconds — this is most of a live preview's latency.
    private static func run(_ executable: URL, _ arguments: [String], in directory: URL, environment: [String: String], timeout: TimeInterval = 20) -> (status: Int32, output: String) {
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment { env[key] = value }
        env["TYPST_FONT_PATHS"] = nil

        var pipeFDs: [Int32] = [0, 0]
        guard pipe(&pipeFDs) == 0 else { return (-1, "Could not start the typesetter.") }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, pipeFDs[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, pipeFDs[1], STDERR_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addchdir_np(&actions, directory.path)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

        let argv: [UnsafeMutablePointer<CChar>?] = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }

        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, executable.path, &actions, &attributes, argv, envp)
        close(pipeFDs[1])
        guard spawned == 0 else { close(pipeFDs[0]); return (-1, String(cString: strerror(spawned))) }

        let reader = FileHandle(fileDescriptor: pipeFDs[0], closeOnDealloc: true)
        var collected = Data()
        let group = DispatchGroup(); group.enter()
        DispatchQueue.global(qos: .userInteractive).async {
            collected = reader.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            kill(pid, SIGKILL)
            var ignored: Int32 = 0
            waitpid(pid, &ignored, 0)
            return (-1, "Typesetting took too long and was stopped.")
        }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        let exitCode: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : -1
        return (exitCode, String(data: collected, encoding: .utf8) ?? "")
    }
}

// MARK: Live preview model

@MainActor
final class TypesetPreview: ObservableObject {
    struct Request: Equatable {
        let text: String
        let cardURL: URL?
        let portrait: Bool
        let fontSize: Double
        let dotGrid: Bool
        let engine: TypesetEngine
        let wantsDocument: Bool
        var color: PrintColor = .black
        var themes: Bool = false
    }

    @Published private(set) var cardPDF: Data?
    @Published private(set) var documentPDF: Data?
    @Published private(set) var error: String?
    @Published private(set) var busy = false
    @Published private(set) var generation = 0
    private var lastRequest: Request?
    private var queued: Request?
    private var inFlight = false
    private var latexDelay: DispatchWorkItem?

    var pageCount: Int { cardPDF.flatMap { PDFDocument(data: $0)?.pageCount } ?? 0 }

    /// Typst renders immediately — no debounce. While a render runs, only the newest
    /// request waits, and it starts the moment the current one finishes. LaTeX (seconds per
    /// render) waits for a short pause in typing instead.
    /// Timings for the typing benchmark (KASTER_TYPING_BENCH); nil in normal use.
    struct Benchmark { var keystroke: Date?; var requested: [Double] = []; var rendered: [Double] = [] }
    static var benchmark: Benchmark?
    func request(_ request: Request) {
        guard request != lastRequest else { return }
        if let start = Self.benchmark?.keystroke { Self.benchmark?.requested.append(Date().timeIntervalSince(start) * 1000); Self.benchmark?.keystroke = nil }
        let engineChanged = lastRequest?.engine != request.engine
        lastRequest = request
        if engineChanged { cardPDF = nil; documentPDF = nil; error = nil }
        latexDelay?.cancel()
        if request.engine == .latex {
            let work = DispatchWorkItem { [weak self] in self?.enqueue(request) }
            latexDelay = work
            busy = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        } else {
            enqueue(request)
        }
    }

    private func enqueue(_ request: Request) {
        queued = request
        startIfIdle()
    }

    private func startIfIdle() {
        guard !inFlight, let request = queued else { return }
        queued = nil
        inFlight = true
        busy = true
        let renderStart = Date()
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let card = KasterTypesetter.prepare(request.text, cardURL: request.cardURL, links: true, themes: request.themes)
            // Card and document typeset in parallel.
            var cardResult: Result<Data, TypesetError> = .failure(.failed(""))
            var documentResult: Result<Data, TypesetError>?
            let group = DispatchGroup()
            DispatchQueue.global(qos: .userInteractive).async(group: group) {
                cardResult = KasterTypesetter.render([card], layout: .card(portrait: request.portrait, fontSize: request.fontSize, dotGrid: request.dotGrid), engine: request.engine, color: request.color)
            }
            if request.wantsDocument {
                DispatchQueue.global(qos: .userInteractive).async(group: group) {
                    documentResult = KasterTypesetter.render([card], layout: .document(fontSize: 11), engine: request.engine, color: request.color)
                }
            }
            group.wait()
            let rendered = Date().timeIntervalSince(renderStart) * 1000
            DispatchQueue.main.async {
                Self.benchmark?.rendered.append(rendered)
                guard let self else { return }
                self.inFlight = false
                // Results are applied in order, so the preview never steps backwards.
                if request.engine == self.lastRequest?.engine {
                    switch cardResult {
                    case .success(let data): self.cardPDF = data; self.error = nil
                    case .failure(let failure): self.error = failure.localizedDescription
                    }
                    if case .success(let data)? = documentResult { self.documentPDF = data }
                    self.generation += 1
                }
                self.busy = self.queued != nil
                self.startIfIdle()
            }
        }
    }

    func reset() { lastRequest = nil; cardPDF = nil; documentPDF = nil; error = nil }
}

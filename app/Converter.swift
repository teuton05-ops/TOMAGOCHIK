import AppKit
import AVFoundation
import PDFKit
import UniformTypeIdentifiers

/// Во что питомец умеет превращать файлы из зубов.
enum Format: String, CaseIterable {
    case jpeg = "JPEG", png = "PNG", pdf = "PDF", mp4 = "MP4", epub = "EPUB"

    var ext: String { self == .jpeg ? "jpg" : rawValue.lowercased() }

    var type: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .pdf: .pdf
        case .mp4: .mpeg4Movie
        case .epub: .epub
        }
    }
}

struct ConvertError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// Конвертация средствами macOS, без сторонних программ:
/// картинки → JPEG, PNG, PDF (несколько картинок — один PDF, страница на картинку);
/// PDF → JPEG, PNG (картинка на страницу), EPUB (только текст);
/// видео → MP4; тексты (txt, md, rtf, doc, docx, odt, html) → PDF, EPUB.
/// Результат кладётся рядом с оригиналом, оригинал не трогается.
enum Converter {
    enum Kind { case image, pdf, movie, text }

    static func kind(of url: URL) -> Kind? {
        guard !url.hasDirectoryPath, let type = type(of: url) else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) {
            let readable = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
            return readable.contains(type.identifier) ? .image : nil  // SVG и прочее, что ImageIO не читает, — мимо
        }
        if type.conforms(to: .movie) { return .movie }
        if markdown(url) || type.conforms(to: .text) || textDocuments.contains(type.identifier) {
            return .text
        }
        return nil
    }

    private static let textDocuments: Set<String> = [
        "org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc",
        "org.oasis-open.opendocument.text", "com.apple.webarchive",
    ]

    static func type(of url: URL) -> UTType? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? UTType(filenameExtension: url.pathExtension)
    }

    private static func markdown(_ url: URL) -> Bool {
        ["md", "markdown"].contains(url.pathExtension.lowercased())
    }

    static func targets(_ kind: Kind) -> [Format] {
        switch kind {
        case .image: [.jpeg, .png, .pdf]
        case .pdf: [.jpeg, .png, .epub]
        case .movie: [.mp4]
        case .text: [.pdf, .epub]
        }
    }

    /// Можно ли превратить файл в этот формат: тип подходит и это не тот же самый формат.
    static func can(_ url: URL, to format: Format) -> Bool {
        guard let kind = kind(of: url), targets(kind).contains(format) else { return false }
        return !(type(of: url)?.conforms(to: format.type) ?? false)
    }

    /// Готовые файлы и сколько не вышло.
    static func convert(_ urls: [URL], to format: Format) async -> (done: [URL], failed: [String]) {
        var done: [URL] = [], failed: [String] = []
        let files = urls.filter { can($0, to: format) }
        // Несколько картинок в PDF — одной книжкой
        let images = format == .pdf ? files.filter { kind(of: $0) == .image } : []
        if !images.isEmpty {
            do { done.append(try imagesToPDF(images)) } catch { failed.append(images[0].lastPathComponent) }
        }
        for url in files where !images.contains(url) {
            do {
                switch (kind(of: url), format) {
                case (.image, _): done.append(try image(url, to: format))
                case (.pdf, .epub): done.append(try epub(from: pdfText(url), title: url.deletingPathExtension().lastPathComponent, next: url))
                case (.pdf, _): done += try pdfToImages(url, format)
                case (.movie, _): done.append(try await mp4(url, preset: AVAssetExportPresetHighestQuality, dest: output(next: url, ext: "mp4")))
                case (.text, .pdf): done.append(try textToPDF(await attributed(url), next: url))
                case (.text, _): done.append(try epub(from: await attributed(url), title: url.deletingPathExtension().lastPathComponent, next: url))
                case (nil, _): break
                }
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        return (done, failed)
    }

    /// Свободное имя рядом с оригиналом: «фото.png», «фото 2.png»…
    static func output(next source: URL, name: String? = nil, ext: String) -> URL {
        let folder = source.deletingLastPathComponent()
        let base = name ?? source.deletingPathExtension().lastPathComponent
        var url = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }

    // MARK: - Картинки

    /// Картинка, уже повёрнутая по EXIF — иначе фото с телефона ложатся боком.
    /// maxPixel уменьшает длинную сторону; без него — полный размер.
    static func orientedImage(_ url: URL, maxPixel: Int? = nil) throws -> (CGImage, dpi: CGFloat) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              let image = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: min(max(w, h), maxPixel ?? .max),
              ] as CFDictionary)
        else { throw ConvertError("Не читается картинка") }
        return (image, props[kCGImagePropertyDPIWidth] as? CGFloat ?? 72)
    }

    private static func image(_ url: URL, to format: Format) throws -> URL {
        let (image, _) = try orientedImage(url)
        let dest = output(next: url, ext: format.ext)
        try write(image, to: dest, as: format)
        return dest
    }

    static func write(_ image: CGImage, to dest: URL, as format: Format, quality: Double = 0.9) throws {
        guard let out = CGImageDestinationCreateWithURL(dest as CFURL, format.type.identifier as CFString, 1, nil)
        else { throw ConvertError("Не записать \(dest.lastPathComponent)") }
        if format == .jpeg {
            // В JPEG нет прозрачности: прозрачное без подложки стало бы чёрным
            CGImageDestinationAddImage(out, onWhite(image), [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        } else {
            CGImageDestinationAddImage(out, image, nil)
        }
        guard CGImageDestinationFinalize(out) else { throw ConvertError("Не записать \(dest.lastPathComponent)") }
    }

    private static func onWhite(_ image: CGImage) -> CGImage {
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }
        ctx.setFillColor(.white)
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage() ?? image
    }

    private static func imagesToPDF(_ urls: [URL]) throws -> URL {
        let dest = output(next: urls[0], ext: "pdf")
        guard let ctx = CGContext(dest as CFURL, mediaBox: nil, nil) else { throw ConvertError("Не создать PDF") }
        for url in urls {
            let (image, dpi) = try orientedImage(url)
            var page = CGRect(x: 0, y: 0, width: CGFloat(image.width) * 72 / dpi, height: CGFloat(image.height) * 72 / dpi)
            ctx.beginPage(mediaBox: &page)
            ctx.draw(image, in: page)
            ctx.endPage()
        }
        ctx.closePDF()
        return dest
    }

    // MARK: - PDF

    /// Страница — картинка в двойном разрешении, на белом. Одна страница — без номера в имени.
    private static func pdfToImages(_ url: URL, _ format: Format) throws -> [URL] {
        let pages = try pdfPageImages(url)
        let base = url.deletingPathExtension().lastPathComponent
        return try pages.enumerated().map { i, image in
            let dest = output(next: url, name: pages.count == 1 ? base : "\(base)-\(i + 1)", ext: format.ext)
            try write(image, to: dest, as: format)
            return dest
        }
    }

    static func pdfPageImages(_ url: URL, scale: CGFloat = 2) throws -> [CGImage] {
        guard let doc = CGPDFDocument(url as CFURL), doc.numberOfPages > 0, !doc.isEncrypted || doc.isUnlocked
        else { throw ConvertError("Не открыть PDF") }
        return (1...doc.numberOfPages).compactMap { i in
            guard let page = doc.page(at: i) else { return nil }
            var box = page.getBoxRect(.cropBox).size
            if page.rotationAngle % 180 != 0 { box = CGSize(width: box.height, height: box.width) }
            let w = Int(box.width * scale), h = Int(box.height * scale)
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return nil }
            ctx.setFillColor(.white)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: scale, y: scale)
            ctx.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: box), rotate: 0, preserveAspectRatio: true))
            ctx.drawPDFPage(page)
            return ctx.makeImage()
        }
    }

    private static func pdfText(_ url: URL) throws -> NSAttributedString {
        guard let doc = PDFDocument(url: url) else { throw ConvertError("Не открыть PDF") }
        let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConvertError("В PDF нет текста") }
        return NSAttributedString(string: text, attributes: [.font: body])
    }

    // MARK: - Видео

    static func mp4(_ url: URL, preset: String, dest: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset),
              session.supportedFileTypes.contains(.mp4)
        else { throw ConvertError("Видео не перегнать в MP4") }
        session.outputURL = dest
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { done in session.exportAsynchronously { done.resume() } }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: dest)
            throw ConvertError(session.error?.localizedDescription ?? "Видео не перегнать в MP4")
        }
        return dest
    }

    // MARK: - Тексты

    private static let body = NSFont.systemFont(ofSize: 12)

    private static func attributed(_ url: URL) async throws -> NSAttributedString {
        if markdown(url) { return try fromMarkdown(String(contentsOf: url, encoding: .utf8)) }
        // HTML и веб-архивы AppKit разбирает через WebKit — только на главном потоке
        if type(of: url)?.conforms(to: .html) == true || type(of: url)?.identifier == "com.apple.webarchive" {
            return try await MainActor.run { try load(url) }
        }
        return try load(url)
    }

    /// Текст и HTML без указанной кодировки AppKit читает как Latin-1 — сначала пробуем UTF-8.
    private static func load(_ url: URL) throws -> NSAttributedString {
        if type(of: url)?.conforms(to: .plainText) == true || type(of: url)?.conforms(to: .html) == true,
           let text = try? NSAttributedString(url: url, options: [.characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) {
            return text
        }
        return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
    }

    /// Заголовки «#», жирный и курсив; остальная разметка как есть.
    private static func fromMarkdown(_ source: String) throws -> NSAttributedString {
        let out = NSMutableAttributedString()
        for line in source.components(separatedBy: .newlines) {
            let hashes = line.prefix { $0 == "#" }.count
            if (1...6).contains(hashes) {
                let title = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
                let size: CGFloat = hashes == 1 ? 22 : hashes == 2 ? 18 : 15
                out.append(NSAttributedString(string: title + "\n", attributes: [.font: NSFont.boldSystemFont(ofSize: size)]))
                continue
            }
            let parsed = (try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(line)
            for run in parsed.runs {
                let intent = run.inlinePresentationIntent ?? []
                var traits: NSFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
                if intent.contains(.emphasized) { traits.insert(.italic) }
                let font = NSFont(descriptor: body.fontDescriptor.withSymbolicTraits(traits), size: 12) ?? body
                out.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: [.font: font]))
            }
            out.append(NSAttributedString(string: "\n", attributes: [.font: body]))
        }
        return out
    }

    /// Страницы A4 с полями 2 см, текст раскладывает CoreText.
    private static func textToPDF(_ text: NSAttributedString, next url: URL) throws -> URL {
        guard text.length > 0 else { throw ConvertError("Пустой файл") }
        let dest = output(next: url, ext: "pdf")
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(dest as CFURL, mediaBox: &page, nil) else { throw ConvertError("Не создать PDF") }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: page.insetBy(dx: 57, dy: 57), transform: nil)
        var position = 0
        while position < text.length {
            ctx.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: position, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            ctx.endPDFPage()
            let shown = CTFrameGetVisibleStringRange(frame).length
            guard shown > 0 else { break }
            position += shown
        }
        ctx.closePDF()
        return dest
    }

    // MARK: - EPUB

    /// EPUB 3: глава на каждый заголовок (крупный или жирный абзац-строка), оглавление по ним.
    private static func epub(from text: NSAttributedString, title: String, next source: URL) throws -> URL {
        var chapters: [(title: String, html: String)] = []
        let bodySize = mostCommonSize(text)
        (text.string as NSString).enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byParagraphs) { _, range, _, _ in
            let paragraph = text.attributedSubstring(from: range)
            let plain = paragraph.string.trimmingCharacters(in: .whitespaces)
            guard !plain.isEmpty else { return }
            let size = (paragraph.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? bodySize
            if size >= bodySize * 1.25 && plain.count < 120 {
                chapters.append((plain, "<h2>\(escape(plain))</h2>\n"))
            } else {
                if chapters.isEmpty { chapters.append((title, "")) }
                chapters[chapters.count - 1].html += "<p>\(inlineHTML(paragraph))</p>\n"
            }
        }
        guard !chapters.isEmpty else { throw ConvertError("Пустой текст") }

        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: dir) }
        let oebps = dir.appendingPathComponent("OEBPS")
        try fm.createDirectory(at: dir.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try fm.createDirectory(at: oebps, withIntermediateDirectories: true)
        func put(_ text: String, _ path: String) throws {
            try text.write(to: dir.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        try put("application/epub+zip", "mimetype")
        try put("""
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
            </container>
            """, "META-INF/container.xml")
        for (i, chapter) in chapters.enumerated() {
            try put(xhtml(chapter.title, chapter.html), "OEBPS/ch\(i + 1).xhtml")
        }
        let items = chapters.indices.map { #"<item id="ch\#($0 + 1)" href="ch\#($0 + 1).xhtml" media-type="application/xhtml+xml"/>"# }
        let spine = chapters.indices.map { #"<itemref idref="ch\#($0 + 1)"/>"# }
        let modified = ISO8601DateFormatter().string(from: Date()).prefix(19) + "Z"
        try put("""
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id" xml:lang="ru">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="id">urn:uuid:\(UUID().uuidString)</dc:identifier>
                <dc:title>\(escape(title))</dc:title>
                <dc:language>ru</dc:language>
                <meta property="dcterms:modified">\(modified)</meta>
              </metadata>
              <manifest>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                \(items.joined(separator: "\n    "))
              </manifest>
              <spine>\(spine.joined())</spine>
            </package>
            """, "OEBPS/content.opf")
        let toc = chapters.enumerated().map { #"<li><a href="ch\#($0.offset + 1).xhtml">\#(escape($0.element.title))</a></li>"# }
        try put(xhtml("Оглавление", #"<nav epub:type="toc"><h2>Оглавление</h2><ol>\#(toc.joined())</ol></nav>"#), "OEBPS/nav.xhtml")

        // mimetype — первым и без сжатия, иначе читалки не признают книгу
        let dest = output(next: source, ext: "epub")
        try zip(in: dir, ["-X0q", dest.path, "mimetype"])
        try zip(in: dir, ["-Xr9Dq", dest.path, "META-INF", "OEBPS"])
        return dest
    }

    private static func zip(in dir: URL, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.arguments = args
        p.currentDirectoryURL = dir
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ConvertError("Не собрать EPUB") }
    }

    private static func xhtml(_ title: String, _ body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="ru">
        <head><meta charset="UTF-8"/><title>\(escape(title))</title></head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func inlineHTML(_ paragraph: NSAttributedString) -> String {
        var html = ""
        paragraph.enumerateAttribute(.font, in: NSRange(location: 0, length: paragraph.length)) { value, range, _ in
            var piece = escape((paragraph.string as NSString).substring(with: range))
            let traits = (value as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            if traits.contains(.italic) { piece = "<em>\(piece)</em>" }
            if traits.contains(.bold) { piece = "<strong>\(piece)</strong>" }
            html += piece
        }
        return html.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Размер основного текста — тот, которым набрано больше всего символов.
    private static func mostCommonSize(_ text: NSAttributedString) -> CGFloat {
        var counts: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            counts[(value as? NSFont)?.pointSize ?? 12, default: 0] += range.length
        }
        return counts.max { $0.value < $1.value }?.key ?? 12
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .filter { $0 == "\t" || $0 == "\n" || !($0.asciiValue.map { $0 < 32 } ?? false) }  // управляющие символы ломают XML
    }
}

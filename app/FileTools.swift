import AppKit
import AVFoundation
import PDFKit
import Vision

/// Прочие дела с файлами в зубах: достать текст, убрать фон, сжать для отправки.
extension Converter {
    // MARK: - Текст с картинки

    static func canRecognizeText(_ url: URL) -> Bool {
        kind(of: url) == .image || kind(of: url) == .pdf
    }

    /// Текст со всех картинок и страниц подряд. У PDF с текстовым слоем берётся он, скан распознаётся.
    static func recognizeText(_ urls: [URL]) async -> (text: String, failed: [String]) {
        var parts: [String] = [], failed: [String] = []
        for url in urls where canRecognizeText(url) {
            do {
                var text = ""
                if kind(of: url) == .pdf, let layer = PDFDocument(url: url)?.string {
                    text = layer
                }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let images = kind(of: url) == .pdf ? try pdfPageImages(url) : [try orientedImage(url).0]
                    text = try images.map(ocr).joined(separator: "\n\n")
                }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConvertError("Текста нет") }
                parts.append(text)
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        return (parts.joined(separator: "\n\n"), failed)
    }

    /// Точная модель ужимает картинку целиком, и мелкий текст на большой странице пропадает.
    /// Поэтому быстрая модель сначала находит строки, а точная читает каждый блок текста отдельно.
    private static func ocr(_ image: CGImage) throws -> String {
        let blocks = try textBlocks(image)
        if blocks.isEmpty { return try read(image) }
        return try blocks.compactMap { image.cropping(to: $0) }.map(read).joined(separator: "\n")
    }

    private static func read(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        request.recognitionLanguages = ["ru-RU", "en-US"].filter(supported.contains)
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Прямоугольники абзацев в пикселях картинки (начало координат сверху), сверху вниз:
    /// строки с зазором меньше полутора строк склеиваются, вокруг — поле в полстроки.
    private static func textBlocks(_ image: CGImage) throws -> [CGRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        try VNImageRequestHandler(cgImage: image).perform([request])
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let lines = (request.results ?? [])
            .map { CGRect(x: $0.boundingBox.minX * w, y: (1 - $0.boundingBox.maxY) * h, width: $0.boundingBox.width * w, height: $0.boundingBox.height * h) }
            .sorted { $0.minY < $1.minY }
        var blocks: [(rect: CGRect, line: CGFloat)] = []
        for line in lines {
            if let last = blocks.last, line.minY - last.rect.maxY < max(last.line, line.height) * 1.5 {
                blocks[blocks.count - 1].rect = last.rect.union(line)
            } else {
                blocks.append((line, line.height))
            }
        }
        let page = CGRect(x: 0, y: 0, width: w, height: h)
        return blocks.map { $0.rect.insetBy(dx: -$0.line * 0.5 - 8, dy: -$0.line * 0.5 - 8).intersection(page).integral }
    }

    // MARK: - Убрать фон

    /// Вырезка объекта появилась в macOS 14.
    static var canRemoveBackground: Bool {
        if #available(macOS 14, *) { return true }
        return false
    }

    /// PNG «… без фона» того же размера: всё, кроме найденных объектов, прозрачное.
    static func removeBackground(_ urls: [URL]) async -> (done: [URL], failed: [String]) {
        var done: [URL] = [], failed: [String] = []
        for url in urls where kind(of: url) == .image {
            do {
                guard #available(macOS 14, *) else { throw ConvertError("Нужна macOS 14") }
                let (image, _) = try orientedImage(url)
                let handler = VNImageRequestHandler(cgImage: image)
                let request = VNGenerateForegroundInstanceMaskRequest()
                try handler.perform([request])
                guard let found = request.results?.first, !found.allInstances.isEmpty else { throw ConvertError("Не нашёл, что вырезать") }
                let buffer = try found.generateMaskedImage(ofInstances: found.allInstances, from: handler, croppedToInstancesExtent: false)
                let masked = CIImage(cvPixelBuffer: buffer)
                guard let cut = CIContext().createCGImage(masked, from: masked.extent) else { throw ConvertError("Не вырезать") }
                let dest = output(next: url, name: url.deletingPathExtension().lastPathComponent + " без фона", ext: "png")
                try write(cut, to: dest, as: .png)
                done.append(dest)
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        return (done, failed)
    }

    // MARK: - Сжать для отправки

    static func canCompress(_ url: URL) -> Bool {
        [.image, .pdf, .movie].contains(kind(of: url))
    }

    /// Картинки — до 1920 px по длинной стороне, в JPEG (с прозрачностью — в PNG); PDF — картинки внутри
    /// пережимаются в JPEG; видео — MP4 720p. Если меньше не стало, сжатый файл удаляется: исходник и так компактный.
    static func compress(_ urls: [URL]) async -> (done: [URL], small: [String], failed: [String], before: Int64, after: Int64) {
        var done: [URL] = [], small: [String] = [], failed: [String] = []
        var before: Int64 = 0, after: Int64 = 0
        for url in urls where canCompress(url) {
            let name = url.deletingPathExtension().lastPathComponent + " (сжато)"
            do {
                let dest: URL
                switch kind(of: url) {
                case .image:
                    let (image, _) = try orientedImage(url, maxPixel: 1920)
                    let format: Format = hasTransparency(image) ? .png : .jpeg
                    dest = output(next: url, name: name, ext: format.ext)
                    try write(image, to: dest, as: format, quality: 0.75)
                case .pdf:
                    guard #available(macOS 13.4, *) else { throw ConvertError("Нужна macOS 13.4") }
                    guard let doc = PDFDocument(url: url) else { throw ConvertError("Не открыть PDF") }
                    dest = output(next: url, name: name, ext: "pdf")
                    guard doc.write(to: dest, withOptions: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true])
                    else { throw ConvertError("Не записать PDF") }
                default:
                    dest = try await mp4(url, preset: AVAssetExportPreset1280x720, dest: output(next: url, name: name, ext: "mp4"))
                }
                let was = size(url), now = size(dest)
                if now >= was {
                    try? FileManager.default.removeItem(at: dest)
                    small.append(url.lastPathComponent)
                } else {
                    done.append(dest)
                    before += was
                    after += now
                }
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        return (done, small, failed, before, after)
    }

    private static func size(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    /// Есть ли по-настоящему прозрачные пиксели: у скриншотов альфа-канал есть, но весь непрозрачный.
    private static func hasTransparency(_ image: CGImage) -> Bool {
        guard ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo) else { return false }
        let side = 64
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return true }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 250 }
    }
}

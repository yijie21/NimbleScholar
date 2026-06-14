import AppKit
import CoreGraphics
import ImageIO

/// Pulls a paper's teaser/pipeline figure straight out of the PDF when there's no online HTML
/// figure to scrape (many arXiv papers have no HTML version). Heuristic, matching how papers
/// are laid out: the **teaser** is the largest embedded image on the first page; if the first
/// page has no real figure, the **pipeline** is the largest image on the following pages.
/// Returns a downscaled NSImage, or nil when nothing usable is embedded (e.g. vector-only figures).
enum PDFFigureExtractor {
    /// Minimum pixel size for an embedded image to count as a figure (filters logos/icons/rules).
    private static let minSide = 120
    private static let maxAspect = 8.0

    static func extractFigure(fromPDFAt path: String, maxPages: Int = 8) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path),
              let doc = CGPDFDocument(URL(fileURLWithPath: path) as CFURL),
              doc.numberOfPages >= 1 else { return nil }

        // Teaser: the best image on page 1.
        if let teaser = bestImage(in: doc, page: 1) { return makeImage(teaser) }

        // Pipeline: the largest qualifying image across the next few pages.
        let last = min(doc.numberOfPages, maxPages)
        guard last >= 2 else { return nil }
        var best: CGImage?
        var bestArea = 0
        for p in 2...last {
            if let img = bestImage(in: doc, page: p) {
                let area = img.width * img.height
                if area > bestArea { bestArea = area; best = img }
            }
        }
        return best.map(makeImage)
    }

    // MARK: - Per-page image selection

    /// Largest qualifying embedded raster image on a 1-based page.
    private static func bestImage(in doc: CGPDFDocument, page pageNumber: Int) -> CGImage? {
        guard let page = doc.page(at: pageNumber),
              let pageDict = page.dictionary else { return nil }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDict, "Resources", &resources), let res = resources else { return nil }
        var xobj: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(res, "XObject", &xobj), let xobjects = xobj else { return nil }

        var images: [CGImage] = []
        CGPDFDictionaryApplyBlock(xobjects, { _, object, _ in
            var stream: CGPDFStreamRef?
            if CGPDFObjectGetValue(object, .stream, &stream), let stream,
               let sdict = CGPDFStreamGetDictionary(stream),
               let img = decodeImage(stream: stream, dict: sdict) {
                images.append(img)
            }
            return true
        }, nil)

        return images
            .filter { img in
                let w = img.width, h = img.height
                let ratio = Double(max(w, h)) / Double(max(1, min(w, h)))
                return w >= minSide && h >= minSide && ratio <= maxAspect
            }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    // MARK: - Decoding a single image XObject

    private static func decodeImage(stream: CGPDFStreamRef, dict: CGPDFDictionaryRef) -> CGImage? {
        var subtype: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype,
              String(cString: subtype) == "Image" else { return nil }

        // Skip image masks (stencils, not real figures).
        var maskBool: CGPDFBoolean = 0
        if CGPDFDictionaryGetBoolean(dict, "ImageMask", &maskBool), maskBool != 0 { return nil }

        var width: CGPDFInteger = 0, height: CGPDFInteger = 0
        CGPDFDictionaryGetInteger(dict, "Width", &width)
        CGPDFDictionaryGetInteger(dict, "Height", &height)
        guard width >= minSide, height >= minSide else { return nil }

        var format = CGPDFDataFormat.raw
        guard let cfdata = CGPDFStreamCopyData(stream, &format) else { return nil }

        switch format {
        case .jpegEncoded, .jpeg2000:
            guard let src = CGImageSourceCreateWithData(cfdata, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(src, 0, nil)
        case .raw:
            return rawImage(data: cfdata as Data, dict: dict, width: Int(width), height: Int(height))
        @unknown default:
            return nil
        }
    }

    /// Build a CGImage from a raw (uncompressed) 8-bit sample stream. Handles the common
    /// device color spaces; returns nil for ICC/indexed/exotic streams (caller falls back).
    private static func rawImage(data: Data, dict: CGPDFDictionaryRef, width: Int, height: Int) -> CGImage? {
        var bpc: CGPDFInteger = 0
        CGPDFDictionaryGetInteger(dict, "BitsPerComponent", &bpc)
        guard bpc == 8 else { return nil }

        guard let (space, components) = colorSpace(dict) else { return nil }
        let bytesPerRow = width * components
        guard data.count >= bytesPerRow * height,
              let provider = CGDataProvider(data: data as CFData) else { return nil }

        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 8 * components, bytesPerRow: bytesPerRow,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func colorSpace(_ dict: CGPDFDictionaryRef) -> (CGColorSpace, Int)? {
        var name: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dict, "ColorSpace", &name), let name else { return nil }
        switch String(cString: name) {
        case "DeviceRGB", "RGB":   return (CGColorSpaceCreateDeviceRGB(), 3)
        case "DeviceGray", "G":    return (CGColorSpaceCreateDeviceGray(), 1)
        case "DeviceCMYK", "CMYK": return (CGColorSpaceCreateDeviceCMYK(), 4)
        default:                   return nil   // ICCBased / Indexed / arrays unsupported
        }
    }

    // MARK: - Output

    /// Normalize into an sRGB NSImage capped at `maxDim` (keeps the cache small + fixes CMYK).
    private static func makeImage(_ cg: CGImage, maxDim: CGFloat = 720) -> NSImage {
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxDim / max(w, h))
        let nw = max(1, Int(w * scale)), nh = max(1, Int(h * scale))
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        if let out = ctx.makeImage() { return NSImage(cgImage: out, size: NSSize(width: nw, height: nh)) }
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
    }
}

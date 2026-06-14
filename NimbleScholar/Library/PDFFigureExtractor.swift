import AppKit
import CoreGraphics
import ImageIO

/// Pulls a paper's teaser/pipeline figure straight out of the PDF when there's no online HTML
/// figure to scrape (many arXiv papers have no HTML version).
///
/// A teaser is usually several image tiles placed together (plus vector labels), so extracting a
/// single embedded image would return just one tile (a crop). Instead we scan the page content
/// stream to find *where* images are drawn, union those rectangles into the whole figure region,
/// and render that region — so the card shows the complete teaser as laid out on the page.
///
/// Strategy: the **teaser** is the figure region on page 1; if page 1 has none, the **pipeline**
/// is the largest figure region across the following pages. Falls back to a single embedded image,
/// then (caller) to rendering the whole first page, for vector-only / rotated / form-wrapped PDFs.
enum PDFFigureExtractor {
    private static let minSidePts: CGFloat = 36     // ignore tiny placed images (rules/icons)
    private static let maxAspect: CGFloat = 12
    private static let minRegionSide: CGFloat = 64  // a real figure region is at least this big

    static func extractFigure(fromPDFAt path: String, maxPages: Int = 8) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path),
              let doc = CGPDFDocument(URL(fileURLWithPath: path) as CFURL),
              doc.numberOfPages >= 1 else { return nil }

        // Teaser: the figure region on page 1.
        if let page = doc.page(at: 1),
           let region = figureRegion(of: page),
           let img = render(region: region, of: page) {
            return img
        }

        // Pipeline: the page (2…N) with the largest figure region.
        let last = min(doc.numberOfPages, maxPages)
        if last >= 2 {
            var best: (page: CGPDFPage, region: CGRect, area: CGFloat)?
            for p in 2...last {
                guard let page = doc.page(at: p), let region = figureRegion(of: page) else { continue }
                let area = region.width * region.height
                if area > (best?.area ?? 0) { best = (page, region, area) }
            }
            if let best, let img = render(region: best.region, of: best.page) { return img }
        }

        // No renderable region anywhere → fall back to a single embedded image.
        for p in 1...min(doc.numberOfPages, maxPages) {
            if let page = doc.page(at: p), let cg = largestImage(of: page) { return makeImage(cg) }
        }
        return nil
    }

    // MARK: - Figure region via content-stream image placements

    /// State threaded through the content-stream scanner via its `info` pointer.
    private final class ScanState {
        var ctm = CGAffineTransform.identity
        var stack: [CGAffineTransform] = []
        var rects: [CGRect] = []
        let imageNames: Set<String>
        init(imageNames: Set<String>) { self.imageNames = imageNames }
    }

    /// Bounding box (page user space) of the images that make up the figure on this page, or nil.
    private static func figureRegion(of page: CGPDFPage) -> CGRect? {
        let names = imageXObjectNames(of: page)
        guard !names.isEmpty else { return nil }

        let state = ScanState(imageNames: names)
        guard let table = CGPDFOperatorTableCreate() else { return nil }
        defer { CGPDFOperatorTableRelease(table) }
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            let s = Unmanaged<ScanState>.fromOpaque(info!).takeUnretainedValue()
            s.stack.append(s.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            let s = Unmanaged<ScanState>.fromOpaque(info!).takeUnretainedValue()
            if let last = s.stack.popLast() { s.ctm = last }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let s = Unmanaged<ScanState>.fromOpaque(info!).takeUnretainedValue()
            var a: CGPDFReal = 0, b: CGPDFReal = 0, c: CGPDFReal = 0, d: CGPDFReal = 0, e: CGPDFReal = 0, f: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &f), CGPDFScannerPopNumber(scanner, &e),
                  CGPDFScannerPopNumber(scanner, &d), CGPDFScannerPopNumber(scanner, &c),
                  CGPDFScannerPopNumber(scanner, &b), CGPDFScannerPopNumber(scanner, &a) else { return }
            s.ctm = CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f).concatenating(s.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            let s = Unmanaged<ScanState>.fromOpaque(info!).takeUnretainedValue()
            var namePtr: UnsafePointer<Int8>?
            guard CGPDFScannerPopName(scanner, &namePtr), let namePtr,
                  s.imageNames.contains(String(cString: namePtr)) else { return }
            // The image occupies the unit square mapped through the current matrix.
            s.rects.append(CGRect(x: 0, y: 0, width: 1, height: 1).applying(s.ctm).standardized)
        }

        let content = CGPDFContentStreamCreateWithPage(page)
        let scanner = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(state).toOpaque())
        _ = CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(content)

        // Keep figure-sized placements; union them into one region.
        let figs = state.rects.filter { r in
            let ratio = max(r.width, r.height) / max(1, min(r.width, r.height))
            return r.width >= minSidePts && r.height >= minSidePts && ratio <= maxAspect
        }
        guard let first = figs.first else { return nil }
        var region = figs.dropFirst().reduce(first) { $0.union($1) }

        // Clamp to the page and require a real size.
        region = region.intersection(page.getBoxRect(.mediaBox))
        guard region.width >= minRegionSide, region.height >= minRegionSide else { return nil }
        return region
    }

    /// Names of XObjects on the page whose subtype is Image.
    private static func imageXObjectNames(of page: CGPDFPage) -> Set<String> {
        guard let pageDict = page.dictionary else { return [] }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDict, "Resources", &resources), let res = resources else { return [] }
        var xobj: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(res, "XObject", &xobj), let xobjects = xobj else { return [] }

        var names = Set<String>()
        CGPDFDictionaryApplyBlock(xobjects, { key, object, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let sdict = CGPDFStreamGetDictionary(stream) else { return true }
            var subtype: UnsafePointer<CChar>?
            if CGPDFDictionaryGetName(sdict, "Subtype", &subtype), let subtype,
               String(cString: subtype) == "Image" {
                names.insert(String(cString: key))
            }
            return true
        }, nil)
        return names
    }

    /// Render a page-user-space region to an NSImage (unrotated pages only).
    private static func render(region: CGRect, of page: CGPDFPage, maxDim: CGFloat = 1000) -> NSImage? {
        guard page.rotationAngle == 0 else { return nil }   // skip rotated pages (region wouldn't align)
        let scale = max(0.1, min(maxDim / max(region.width, region.height), 4))
        let pw = max(1, Int(region.width * scale)), ph = max(1, Int(region.height * scale))
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -region.minX, y: -region.minY)
        ctx.drawPDFPage(page)
        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: pw, height: ph))
    }

    // MARK: - Single embedded image (fallback when there's no renderable region)

    private static func largestImage(of page: CGPDFPage) -> CGImage? {
        guard let pageDict = page.dictionary else { return nil }
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
                return w >= 120 && h >= 120 && ratio <= 8
            }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    private static func decodeImage(stream: CGPDFStreamRef, dict: CGPDFDictionaryRef) -> CGImage? {
        var subtype: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype,
              String(cString: subtype) == "Image" else { return nil }
        var maskBool: CGPDFBoolean = 0
        if CGPDFDictionaryGetBoolean(dict, "ImageMask", &maskBool), maskBool != 0 { return nil }

        var width: CGPDFInteger = 0, height: CGPDFInteger = 0
        CGPDFDictionaryGetInteger(dict, "Width", &width)
        CGPDFDictionaryGetInteger(dict, "Height", &height)
        guard width >= 120, height >= 120 else { return nil }

        var format = CGPDFDataFormat.raw
        guard let cfdata = CGPDFStreamCopyData(stream, &format) else { return nil }
        if format == .raw {
            return rawImage(data: cfdata as Data, dict: dict, width: Int(width), height: Int(height))
        }
        guard let src = CGImageSourceCreateWithData(cfdata, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func rawImage(data: Data, dict: CGPDFDictionaryRef, width: Int, height: Int) -> CGImage? {
        var bpc: CGPDFInteger = 0
        CGPDFDictionaryGetInteger(dict, "BitsPerComponent", &bpc)
        guard bpc == 8, let (space, components) = colorSpace(dict) else { return nil }
        let bytesPerRow = width * components
        guard data.count >= bytesPerRow * height, let provider = CGDataProvider(data: data as CFData) else { return nil }
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
        default:                   return nil
        }
    }

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

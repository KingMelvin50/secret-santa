// Cuts a floating sticker-head out of each photo, using Apple's Vision framework (macOS 13+, no installs).
// Run it through tools/cut-heads.sh, which compiles this file and calls:
//
//   extract-heads <photos-dir> <heads-dir> [tunes.json]
//
// For every photo it finds the biggest face, keeps that person's head (hair, hat and ears included,
// neck and shoulders not), adds a white sticker border, and writes:
//
//   <heads-dir>/<name>.webp      one per photo (.png if the `cwebp` tool isn't installed)
//   <heads-dir>/heads.js         the list of people the site reads
//   <photos-dir>/_cutouts.png    every cut-out on one sheet, for checking them by eye
//
// The photo's file name is the person's name: "Mary Kate.jpg" is shown as "Mary Kate".

import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

// ---------- tuning ----------

// The defaults suit most photos. To change them for one person, add an entry to tools/tunes.json:
//   { "sam": { "sxTopRight": 1.03, "skullW": 1.12 }, "jo": { "bgKey": 42 } }
// "Left" and "right" mean the sides of the photo as you look at it.
struct Tune {
    var sxTop = 1.38  // sideways slack at ear level (keeps ears and sideburns); lower = tighter
    var sxChin = 1.06  // sideways slack at the chin
    var chinDrop = 0.07  // extra kept below the jawline, as a fraction of jaw depth
    var earEnd = 0.38  // how far down the jaw (0 = ear level, 1 = chin) the ears stop
    var jawStart = 0.72  // ...and where the cut hugs the jaw
    var cropUp = 1.7  // room above the face box, in face heights (raise for tall hats)
    var cropSide = 0.9  // room either side, in face widths
    var maskLo: Float = 0.5  // person-mask values below this become transparent
    var maskHi: Float = 0.88  // ...and above this fully opaque
    // Normally everything above ear level is kept (hats, helmets, big hair). When something else is up
    // there (a hand on the head, a neighbour), set these to keep only a rounded cap instead:
    var skullW: Double? = nil  // cap half-width, as a multiple of the jaw's half-width (try 1.12)
    var skullH: Double? = nil  // cap height above ear level, as a multiple of ear-to-chin distance (try 1.15)
    // When something is pressed against one side only (a hand, a neighbour's cheek), these replace
    // sxTop and skullW on that side of the photo:
    var sxTopLeft: Double? = nil
    var sxTopRight: Double? = nil
    var skullWLeft: Double? = nil
    var skullWRight: Double? = nil
    // For studio headshots where the mask swallows a plain backdrop: peel off anything within this
    // colour distance (0–441) of the backdrop (try 42). Leave unset for ordinary photos.
    var bgKey: Double? = nil
}

/// Lowercase, ASCII, dashes for everything else: "Mary Kate" -> "mary-kate", "José" -> "jose".
func slug(_ s: String) -> String {
    var out = ""
    for ch in s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased().unicodeScalars {
        if ch.isASCII && CharacterSet.alphanumerics.contains(ch) {
            out.unicodeScalars.append(ch)
        } else if !out.isEmpty && !out.hasSuffix("-") {
            out += "-"
        }
    }
    while out.hasSuffix("-") { out.removeLast() }
    return out
}

/// "Mary Kate" stays as typed; an all-lowercase file name gets capitals ("mary kate" -> "Mary Kate").
func displayName(_ base: String) -> String {
    let spaced = base.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    return spaced == spaced.lowercased() ? spaced.capitalized : spaced
}

func loadTunes(_ path: String?) -> [String: Tune] {
    guard let path = path, let data = FileManager.default.contents(atPath: path) else { return [:] }
    guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        print("! \(path) isn't valid JSON, so it was ignored")
        return [:]
    }
    var out: [String: Tune] = [:]
    for (who, value) in raw {
        guard let knobs = value as? [String: Any] else { continue }  // lets "_note": "..." entries through
        var t = Tune()
        for (k, any) in knobs {
            guard let x = (any as? NSNumber)?.doubleValue else { continue }
            switch k {
            case "sxTop": t.sxTop = x
            case "sxChin": t.sxChin = x
            case "chinDrop": t.chinDrop = x
            case "earEnd": t.earEnd = x
            case "jawStart": t.jawStart = x
            case "cropUp": t.cropUp = x
            case "cropSide": t.cropSide = x
            case "maskLo": t.maskLo = Float(x)
            case "maskHi": t.maskHi = Float(x)
            case "skullW": t.skullW = x
            case "skullH": t.skullH = x
            case "sxTopLeft": t.sxTopLeft = x
            case "sxTopRight": t.sxTopRight = x
            case "skullWLeft": t.skullWLeft = x
            case "skullWRight": t.skullWRight = x
            case "bgKey": t.bgKey = x
            default: print("! \(path): \"\(k)\" (for \(who)) isn't a setting, so it was ignored")
            }
        }
        out[slug(who)] = t
    }
    return out
}

let outSize = 460.0  // longest side of the head itself, before the sticker border
let borderFrac = 0.034  // sticker border thickness relative to outSize

// ---------- helpers ----------

struct Mask {
    let w: Int
    let h: Int
    var d: [Float]

    /// Bilinear sample at normalised top-left coordinates.
    func sample(_ u: Double, _ v: Double) -> Float {
        let x = min(max(u * Double(w) - 0.5, 0), Double(w - 1))
        let y = min(max(v * Double(h) - 0.5, 0), Double(h - 1))
        let x0 = Int(x), y0 = Int(y)
        let x1 = min(x0 + 1, w - 1), y1 = min(y0 + 1, h - 1)
        let tx = Float(x - Double(x0)), ty = Float(y - Double(y0))
        let a = d[y0 * w + x0] * (1 - tx) + d[y0 * w + x1] * tx
        let b = d[y1 * w + x0] * (1 - tx) + d[y1 * w + x1] * tx
        return a * (1 - ty) + b * ty
    }
}

func mask(from pb: CVPixelBuffer) -> Mask? {
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
    let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
    let bpr = CVPixelBufferGetBytesPerRow(pb)
    guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
    var d = [Float](repeating: 0, count: w * h)
    switch CVPixelBufferGetPixelFormatType(pb) {
    case kCVPixelFormatType_OneComponent32Float:
        for y in 0..<h {
            let row = (base + y * bpr).assumingMemoryBound(to: Float32.self)
            for x in 0..<w { d[y * w + x] = row[x] }
        }
    case kCVPixelFormatType_OneComponent8:
        for y in 0..<h {
            let row = (base + y * bpr).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w { d[y * w + x] = Float(row[x]) / 255 }
        }
    default:
        return nil
    }
    return Mask(w: w, h: h, d: d)
}

func loadImage(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 4096
    let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 4096
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,  // bake in EXIF rotation
        kCGImageSourceThumbnailMaxPixelSize: max(w, h),
    ]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
}

func rgbaContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func writePNG(_ img: CGImage, _ url: URL) {
    guard
        let dst = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
}

func smoothstep(_ lo: Float, _ hi: Float, _ x: Float) -> Float {
    let t = max(0, min(1, (x - lo) / (hi - lo)))
    return t * t * (3 - 2 * t)
}

func boxBlur(_ src: [Float], _ w: Int, _ h: Int, _ r: Int) -> [Float] {
    var tmp = [Float](repeating: 0, count: w * h), out = [Float](repeating: 0, count: w * h)
    let n = Float(2 * r + 1)
    for y in 0..<h {
        var acc: Float = 0
        for x in -r...r { acc += src[y * w + min(max(x, 0), w - 1)] }
        for x in 0..<w {
            tmp[y * w + x] = acc / n
            acc += src[y * w + min(x + r + 1, w - 1)] - src[y * w + max(x - r, 0)]
        }
    }
    for x in 0..<w {
        var acc: Float = 0
        for y in -r...r { acc += tmp[min(max(y, 0), h - 1) * w + x] }
        for y in 0..<h {
            out[y * w + x] = acc / n
            acc += tmp[min(y + r + 1, h - 1) * w + x] - tmp[max(y - r, 0) * w + x]
        }
    }
    return out
}

func catmullRom(_ p: [(Double, Double)], steps: Int) -> [(Double, Double)] {
    guard p.count >= 3 else { return p }
    func f(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ t: Double) -> Double {
        0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t * t * t)
    }
    var out: [(Double, Double)] = []
    for i in 0..<(p.count - 1) {
        let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, p.count - 1)]
        for s in 0..<steps {
            let t = Double(s) / Double(steps)
            out.append((f(p0.0, p1.0, p2.0, p3.0, t), f(p0.1, p1.1, p2.1, p3.1, t)))
        }
    }
    out.append(p[p.count - 1])
    return out
}

func centroid(_ pts: [CGPoint]) -> (Double, Double) {
    let n = Double(max(pts.count, 1))
    return (pts.reduce(0) { $0 + Double($1.x) } / n, pts.reduce(0) { $0 + Double($1.y) } / n)
}

/// The mask of whichever person the face belongs to.
func personMask(_ handler: VNImageRequestHandler, faceU: Double, faceV: Double, faceW: Double, faceH: Double) -> Mask? {
    func score(_ m: Mask) -> Float {
        var s: Float = 0
        for j in 0..<10 {
            for i in 0..<10 {
                s += m.sample(faceU + faceW * (Double(i) + 0.5) / 10, faceV + faceH * (Double(j) + 0.5) / 10)
            }
        }
        return s / 100
    }
    if #available(macOS 14.0, *) {
        let req = VNGeneratePersonInstanceMaskRequest()
        try? handler.perform([req])
        if let obs = req.results?.first {
            var best: (Float, Mask)?
            for i in obs.allInstances {
                guard let pb = try? obs.generateScaledMaskForImage(forInstances: IndexSet(integer: i), from: handler),
                    let m = mask(from: pb)
                else { continue }
                let s = score(m)
                if best == nil || s > best!.0 { best = (s, m) }
            }
            if let b = best, b.0 > 0.4 { return b.1 }
        }
    }
    let req = VNGeneratePersonSegmentationRequest()
    req.qualityLevel = .accurate
    req.outputPixelFormat = kCVPixelFormatType_OneComponent8
    try? handler.perform([req])
    if let pb = req.results?.first?.pixelBuffer { return mask(from: pb) }
    return nil
}

// ---------- one photo -> one head ----------

func process(_ url: URL, name: String, tune: Tune, outDir: URL) -> (info: [String: Any], image: CGImage)? {
    guard let cg = loadImage(url) else {
        print("✗ \(name): could not read image")
        return nil
    }
    let W = Double(cg.width), H = Double(cg.height)
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])

    // 1. Biggest face in the photo.
    let faceReq = VNDetectFaceLandmarksRequest()
    try? handler.perform([faceReq])
    guard
        let face = faceReq.results?.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }),
        let lm = face.landmarks, let contour = lm.faceContour, let le = lm.leftEye, let re = lm.rightEye
    else {
        print("✗ \(name): no face found")
        return nil
    }
    let bb = face.boundingBox
    let fx = Double(bb.minX) * W, fw = Double(bb.width) * W
    let fy = (1 - Double(bb.maxY)) * H, fh = Double(bb.height) * H
    let size = CGSize(width: W, height: H)
    func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: CGFloat(H) - p.y) }  // Vision is bottom-left
    let eyeA = centroid(le.pointsInImage(imageSize: size).map(flip))
    let eyeB = centroid(re.pointsInImage(imageSize: size).map(flip))

    // Face frame: origin between the eyes, `hx` along the eye line, `dn` towards the chin.
    let c = ((eyeA.0 + eyeB.0) / 2, (eyeA.1 + eyeB.1) / 2)
    var hx = (eyeB.0 - eyeA.0, eyeB.1 - eyeA.1)
    if hx.0 < 0 { hx = (-hx.0, -hx.1) }
    let hl = (hx.0 * hx.0 + hx.1 * hx.1).squareRoot()
    hx = (hx.0 / hl, hx.1 / hl)
    let dn = (-hx.1, hx.0)
    func toImage(_ a: Double, _ b: Double) -> (Double, Double) {
        (c.0 + a * hx.0 + b * dn.0, c.1 + a * hx.1 + b * dn.1)
    }

    // 2. Jawline in the face frame, pushed out a little so the whole chin and both ears survive.
    var jaw = contour.pointsInImage(imageSize: size).map(flip).map { p -> (Double, Double) in
        let dx = Double(p.x) - c.0, dy = Double(p.y) - c.1
        return (dx * hx.0 + dy * hx.1, dx * dn.0 + dy * dn.1)
    }
    guard jaw.count >= 5 else {
        print("✗ \(name): jawline too short")
        return nil
    }
    if jaw.first!.0 > jaw.last!.0 { jaw.reverse() }  // keep contour order, running left to right
    let b0 = (jaw.first!.1 + jaw.last!.1) / 2  // roughly ear level
    let bChin = jaw.map { $0.1 }.max()!
    let depth = max(bChin - b0, 1)
    if ProcessInfo.processInfo.environment["DEBUG"] != nil {
        let s = jaw.map { String(format: "(%.2f,%.2f)", $0.0 / hl, $0.1 / hl) }.joined(separator: " ")
        print("  \(name) jaw in eye-distances: \(s)")
    }
    let pushed = jaw.map { p -> (Double, Double) in
        let t = min(max((p.1 - b0) / depth, 0), 1)
        // Wide while we're passing the ears, then tight to the jaw so collars and hoods fall away.
        let k = min(max((t - tune.earEnd) / (tune.jawStart - tune.earEnd), 0), 1)
        let top = (p.0 > 0 ? tune.sxTopRight : tune.sxTopLeft) ?? tune.sxTop
        let sx = top + (tune.sxChin - top) * (k * k * (3 - 2 * k))
        return (p.0 * sx, max(b0, b0 + (p.1 - b0) * (1 + tune.chinDrop)))
    }
    let curve = catmullRom(pushed, steps: 8)
    let big = 6 * max(fw, fh)
    // Everything above ear level (or a rounded cap, if asked for), plus the cup under the jaw.
    var poly: [(Double, Double)]
    if let kw = tune.skullW {
        // Each half of the cap follows its own side of the jaw, so a turned head doesn't get a lopsided one.
        let capL = (tune.skullWLeft ?? kw) * (jaw.map { -$0.0 }.max() ?? fw / 2)
        let capR = (tune.skullWRight ?? kw) * (jaw.map { $0.0 }.max() ?? fw / 2)
        let capH = (tune.skullH ?? 1.1) * depth, n = 2.6
        poly = (0...48).map { i -> (Double, Double) in
            let th = Double.pi * Double(i) / 48  // left ear, over the top, to the right ear
            let cs = -cos(th), sn = sin(th)
            return ((cs < 0 ? -capL : capR) * pow(abs(cs), 2 / n), b0 - capH * pow(sn, 2 / n))
        }
    } else {
        poly = [(-big, b0), (-big, -big), (big, -big), (big, b0)]
    }
    poly += curve.reversed()

    // 3. Person mask for the owner of that face. Vision segments far better when the person fills the
    //    frame, so it is shown just the area around the head, enlarged if the head is small in the photo.
    let sx0 = max(0, fx - 1.6 * fw), sx1 = min(W, fx + fw + 1.6 * fw)
    let sy0 = max(0, fy - 2.0 * fh), sy1 = min(H, fy + fh + 1.6 * fh)
    let segW = sx1 - sx0, segH = sy1 - sy0
    let up = min(4, max(1, 900 / max(segW, segH)))
    let segCtx = rgbaContext(Int(segW * up), Int(segH * up))
    segCtx.interpolationQuality = .high
    segCtx.draw(cg, in: CGRect(x: -sx0 * up, y: -(H - sy1) * up, width: W * up, height: H * up))
    guard let segImg = segCtx.makeImage(),
        let pm = personMask(
            VNImageRequestHandler(cgImage: segImg, options: [:]),
            faceU: (fx - sx0) / segW, faceV: (fy - sy0) / segH, faceW: fw / segW, faceH: fh / segH)
    else {
        print("✗ \(name): no person mask")
        return nil
    }

    // 4. Work in a generous crop around the head.
    let cx0 = Int(max(0, fx - tune.cropSide * fw)), cx1 = Int(min(W, fx + fw + tune.cropSide * fw))
    let cy0 = Int(max(0, fy - tune.cropUp * fh)), cy1 = Int(min(H, fy + fh + 0.6 * fh))
    let cw = cx1 - cx0, ch = cy1 - cy0

    let cutCtx = CGContext(
        data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    cutCtx.translateBy(x: 0, y: CGFloat(ch))
    cutCtx.scaleBy(x: 1, y: -1)  // draw in top-left coordinates
    cutCtx.setFillColor(gray: 1, alpha: 1)
    cutCtx.beginPath()
    for (i, p) in poly.enumerated() {
        let q = toImage(p.0, p.1)
        let pt = CGPoint(x: q.0 - Double(cx0), y: q.1 - Double(cy0))
        if i == 0 { cutCtx.move(to: pt) } else { cutCtx.addLine(to: pt) }
    }
    cutCtx.closePath()
    cutCtx.fillPath()
    let cut = cutCtx.data!.bindMemory(to: UInt8.self, capacity: cw * ch)

    var alpha = [Float](repeating: 0, count: cw * ch)
    for y in 0..<ch {
        for x in 0..<cw {
            alpha[y * cw + x] = pm.sample((Double(cx0 + x) + 0.5 - sx0) / segW, (Double(cy0 + y) + 0.5 - sy0) / segH)
        }
    }
    // The mask is coarser than the photo; soften it before thresholding so edges don't stair-step.
    let blurR = max(1, Int((fw * 0.012).rounded()))
    for _ in 0..<2 { alpha = boxBlur(alpha, cw, ch, blurR) }
    for i in 0..<(cw * ch) {
        alpha[i] = smoothstep(tune.maskLo, tune.maskHi, alpha[i]) * Float(cut[i]) / 255
    }

    let ctx = rgbaContext(cw, ch)
    ctx.draw(cg, in: CGRect(x: -Double(cx0), y: -(H - Double(cy0) - Double(ch)), width: W, height: H))
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: cw * ch * 4)

    // Studio headshots: the person mask can swallow a plain backdrop. Peel it off by colour. The
    // backdrop's colour is read from whatever got kept well out to the sides above the ears, where
    // (with no hat) there should be nothing at all.
    if let key = tune.bgKey {
        let halfW = jaw.map { abs($0.0) }.max() ?? fw / 2
        var wings: [Int] = []
        for y in 0..<ch {
            for x in 0..<cw where alpha[y * cw + x] > 0.5 {
                let dx = Double(cx0 + x) - c.0, dy = Double(cy0 + y) - c.1
                let a = dx * hx.0 + dy * hx.1, b = dx * dn.0 + dy * dn.1
                if b < b0 - 0.15 * depth && abs(a) > 1.3 * halfW { wings.append(y * cw + x) }
            }
        }
        if wings.count >= 12 {
            func median(_ ch: Int) -> Double { Double(wings.map { px[$0 * 4 + ch] }.sorted()[wings.count / 2]) }
            let bg = (median(0), median(1), median(2))
            func far(_ i: Int) -> Double {
                let dr = Double(px[i * 4]) - bg.0, dg = Double(px[i * 4 + 1]) - bg.1, db = Double(px[i * 4 + 2]) - bg.2
                return (dr * dr + dg * dg + db * db).squareRoot()
            }
            var gone = [Bool](repeating: false, count: cw * ch)
            var todo = wings.filter { far($0) < key }
            for i in todo { gone[i] = true }
            while let i = todo.popLast() {
                let x = i % cw, y = i / cw
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && ny >= 0 && nx < cw && ny < ch {
                    let j = ny * cw + nx
                    if !gone[j] && alpha[j] > 0 && far(j) < key {
                        gone[j] = true
                        todo.append(j)
                    }
                }
            }
            // ...plus the blended fringe right next to it.
            for _ in 0..<2 {
                let before = gone
                for y in 1..<(ch - 1) {
                    for x in 1..<(cw - 1) {
                        let i = y * cw + x
                        if before[i] || alpha[i] <= 0 || far(i) >= key * 2.2 { continue }
                        if before[i - 1] || before[i + 1] || before[i - cw] || before[i + cw] { gone[i] = true }
                    }
                }
            }
            for i in 0..<(cw * ch) where gone[i] { alpha[i] = 0 }
            alpha = boxBlur(alpha, cw, ch, 1)
        }
    }

    // Keep only the blob connected to the face (drops stray bits of other people).
    var keep = [Bool](repeating: false, count: cw * ch)
    let seedX = min(max(Int(fx + fw / 2) - cx0, 0), cw - 1), seedY = min(max(Int(fy + fh / 2) - cy0, 0), ch - 1)
    var stack = [seedY * cw + seedX]
    keep[stack[0]] = true
    while let i = stack.popLast() {
        let x = i % cw, y = i / cw
        for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
        where nx >= 0 && ny >= 0 && nx < cw && ny < ch {
            let j = ny * cw + nx
            if !keep[j] && alpha[j] > 0.08 {
                keep[j] = true
                stack.append(j)
            }
        }
    }

    var minX = cw, minY = ch, maxX = -1, maxY = -1
    for y in 0..<ch {
        for x in 0..<cw {
            let i = y * cw + x
            let a = keep[i] ? alpha[i] : 0
            if a > 0.03 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
            px[i * 4] = UInt8(Float(px[i * 4]) * a)
            px[i * 4 + 1] = UInt8(Float(px[i * 4 + 1]) * a)
            px[i * 4 + 2] = UInt8(Float(px[i * 4 + 2]) * a)
            px[i * 4 + 3] = UInt8(255 * a)
        }
    }
    guard maxX > minX, maxY > minY,
        let head = ctx.makeImage()?.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    else {
        print("✗ \(name): nothing left after masking")
        return nil
    }

    // 5. Scale down and add the white sticker border.
    let hw = Double(head.width), hh = Double(head.height)
    let scale = outSize / max(hw, hh)
    let r = (borderFrac * outSize).rounded()
    let pad = Int(r) + 3
    let sw = Int((hw * scale).rounded()), sh = Int((hh * scale).rounded())
    let ow = sw + pad * 2, oh = sh + pad * 2
    let out = rgbaContext(ow, oh)
    out.interpolationQuality = .high
    out.draw(head, in: CGRect(x: pad, y: pad, width: sw, height: sh))
    let op = out.data!.bindMemory(to: UInt8.self, capacity: ow * oh * 4)

    var solid = [Bool](repeating: false, count: ow * oh)
    for i in 0..<(ow * oh) { solid[i] = op[i * 4 + 3] >= 128 }
    let ri = Int(r) + 1
    var offsets: [(Int, Int, Double)] = []
    for dy in -ri...ri {
        for dx in -ri...ri {
            let d = Double(dx * dx + dy * dy).squareRoot()
            if d <= r + 1 { offsets.append((dx, dy, d)) }
        }
    }
    offsets.sort { $0.2 < $1.2 }
    for y in 0..<oh {
        for x in 0..<ow {
            let i = y * ow + x
            let ha = Double(op[i * 4 + 3]) / 255
            if ha >= 0.999 { continue }
            var dist = Double.infinity
            for (dx, dy, d) in offsets {
                let nx = x + dx, ny = y + dy
                if nx >= 0 && ny >= 0 && nx < ow && ny < oh && solid[ny * ow + nx] {
                    dist = d
                    break
                }
            }
            let oa = min(max(r - dist + 0.5, 0), 1)  // white border coverage, antialiased
            if oa <= 0 && ha <= 0 { continue }
            let white = (1 - ha) * 255 * oa
            op[i * 4] = UInt8(min(255, Double(op[i * 4]) + white))
            op[i * 4 + 1] = UInt8(min(255, Double(op[i * 4 + 1]) + white))
            op[i * 4 + 2] = UInt8(min(255, Double(op[i * 4 + 2]) + white))
            op[i * 4 + 3] = UInt8(min(255, (ha + (1 - ha) * oa) * 255))
        }
    }
    guard let final = out.makeImage() else { return nil }
    writePNG(final, outDir.appendingPathComponent("\(name).png"))

    // Where a hat would sit: walk up from between the eyes until we leave the head.
    func toOut(_ p: (Double, Double)) -> (Double, Double) {
        ((p.0 - Double(cx0 + minX)) * scale + Double(pad), (p.1 - Double(cy0 + minY)) * scale + Double(pad))
    }
    var crown = c
    var t = 0.0
    while t < 4 * fh {
        let p = toImage(0, -t)
        let x = Int(p.0) - cx0, y = Int(p.1) - cy0
        if x < 0 || y < 0 || x >= cw || y >= ch { break }
        if keep[y * cw + x] && alpha[y * cw + x] > 0.5 { crown = p }
        t += 1
    }
    let co = toOut(crown), fo = toOut(c)
    let roll = atan2(hx.1, hx.0) * 180 / .pi
    _ = fo
    print(String(format: "✓ %@  %dx%d  tilt %.0f°", name, ow, oh, roll))
    let info: [String: Any] = [
        "w": ow, "h": oh, "roll": Int(roll.rounded()),
        "crownX": (co.0 / Double(ow) * 1000).rounded() / 1000, "crownY": (co.1 / Double(oh) * 1000).rounded() / 1000,
    ]
    return (info, final)
}

// ---------- main ----------

func which(_ tool: String) -> String? {
    let dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    return (dirs + ["/opt/homebrew/bin", "/usr/local/bin"]).map { $0 + "/" + tool }
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}

func run(_ exe: String, _ args: [String]) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}

func js(_ s: String) -> String {
    let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed, .withoutEscapingSlashes])
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: extract-heads <photos-dir> <heads-dir> [tunes.json]")
    exit(1)
}
let fm = FileManager.default
let inDir = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2])
let tunes = loadTunes(args.count > 3 ? args[3] : nil)
try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)
let exts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "tif", "tiff"]
let files = ((try? fm.contentsOfDirectory(at: inDir, includingPropertiesForKeys: nil)) ?? [])
    .filter {
        let n = $0.lastPathComponent
        return exts.contains($0.pathExtension.lowercased()) && !n.hasPrefix("_") && !n.hasPrefix(".")
    }
    .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
guard !files.isEmpty else {
    print("No photos in \(inDir.path). Add one per person, named after them (Alex.jpg, Mary Kate.png, ...).")
    exit(1)
}

let cwebp = which("cwebp")
var lines: [String] = [], made: [String] = [], order: [String] = [], failed: [String] = [], sheetHeads: [CGImage] = []
for (i, f) in files.enumerated() {
    let base = f.deletingPathExtension().lastPathComponent
    var id = slug(base)
    if id.isEmpty { id = "head-\(i + 1)" }
    if order.contains(id) {
        print("✗ \(f.lastPathComponent): another photo is already called \"\(id)\"")
        failed.append(f.lastPathComponent)
        continue
    }
    guard let r = process(f, name: id, tune: tunes[id] ?? Tune(), outDir: outDir) else {
        failed.append(f.lastPathComponent)
        continue
    }
    let png = outDir.appendingPathComponent("\(id).png"), webp = outDir.appendingPathComponent("\(id).webp")
    var file = png.lastPathComponent
    if let tool = cwebp, run(tool, ["-quiet", "-q", "86", "-alpha_q", "100", png.path, "-o", webp.path]) {
        try? fm.removeItem(at: png)
        file = webp.lastPathComponent
    } else {
        try? fm.removeItem(at: webp)
    }
    let m = r.info
    lines.append(
        "  { id: \(js(id)), name: \(js(displayName(base))), src: \(js(outDir.lastPathComponent + "/" + file)), "
            + "w: \(m["w"]!), h: \(m["h"]!), crown: [\(m["crownX"]!), \(m["crownY"]!)], roll: \(m["roll"]!) },")
    made.append(file)
    order.append(id)
    sheetHeads.append(r.image)
}
for who in tunes.keys.sorted() where !order.contains(who) {
    print("! tunes.json has settings for \"\(who)\", but there's no photo by that name")
}

// Contact sheet on red, for eyeballing the cut-outs.
if !sheetHeads.isEmpty {
    let gap = 30, perRow = min(4, sheetHeads.count)
    let cellW = (sheetHeads.map { $0.width }.max() ?? 0) + gap, cellH = (sheetHeads.map { $0.height }.max() ?? 0) + gap
    let rows = (sheetHeads.count + perRow - 1) / perRow
    let sheetW = cellW * perRow + gap, sheetH = cellH * rows + gap
    let sheet = rgbaContext(sheetW, sheetH)
    sheet.setFillColor(red: 0.72, green: 0.11, blue: 0.17, alpha: 1)
    sheet.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
    for (i, h) in sheetHeads.enumerated() {
        let col = i % perRow, row = i / perRow
        let x = gap + col * cellW + (cellW - gap - h.width) / 2
        let y = sheetH - gap - (row + 1) * cellH + gap + (cellH - gap - h.height) / 2  // CG origin is bottom-left
        sheet.draw(h, in: CGRect(x: x, y: y, width: h.width, height: h.height))
    }
    let sheetURL = inDir.appendingPathComponent("_cutouts.png")
    if let img = sheet.makeImage() {
        writePNG(img, sheetURL)
        print("Check them by eye: \(sheetURL.path)  (left to right, top to bottom: \(order.joined(separator: ", ")))")
    }
}

guard failed.isEmpty else {
    print("\n\(failed.count) of \(files.count) photos could not be cut: \(failed.joined(separator: ", "))")
    print("Use a photo where that person's face is clear and facing the camera, then run this again.")
    print("\(outDir.lastPathComponent)/heads.js was left as it was.")
    exit(1)
}

let header = """
    // The people on the site: one entry per head. Written by tools/cut-heads.sh from the photos in
    // photos/, so re-run that rather than editing by hand. (To change how a name is spelled, use
    // `names` in config.js.)
    window.HEADS = [

    """
try? (header + lines.joined(separator: "\n") + "\n];\n")
    .write(to: outDir.appendingPathComponent("heads.js"), atomically: true, encoding: .utf8)

// Clear out pictures of anyone who is no longer in photos/ (and the example cartoon heads).
let pictures: Set<String> = ["svg", "png", "webp", "jpg", "jpeg", "gif"]
for old in (try? fm.contentsOfDirectory(at: outDir, includingPropertiesForKeys: nil)) ?? []
where pictures.contains(old.pathExtension.lowercased()) && !made.contains(old.lastPathComponent) {
    try? fm.removeItem(at: old)
    print("  removed \(outDir.lastPathComponent)/\(old.lastPathComponent) (not in \(inDir.lastPathComponent)/ any more)")
}
print("\(order.count) heads written to \(outDir.path)" + (cwebp == nil ? "  (tip: `brew install webp` makes them about 10x smaller)" : ""))

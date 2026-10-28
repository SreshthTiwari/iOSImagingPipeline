import CoreImage
import Foundation

// Compares the original stage-by-stage pipeline (render + JPEG write + reload between
// every stage) with the single-pass Core Image graph, on the same input.
//
//   run.sh <image> [<image> ...] [--runs N] [--megapixels M]
//
// --megapixels resizes each input to about M megapixels first, to approximate a
// phone-sized capture from a smaller test photo.

let ctx = ImagingIO.context
let fm = FileManager.default

var inputs: [String] = []
var runs = 10
var targetMP: Double?

var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--runs": runs = Int(args.removeFirst()) ?? runs
    case "--megapixels": targetMP = Double(args.removeFirst())
    default: inputs.append(a)
    }
}
guard !inputs.isEmpty else {
    FileHandle.standardError.write(Data("usage: run.sh <image>... [--runs N] [--megapixels M]\n".utf8))
    exit(2)
}

func ms(_ body: () throws -> Void) rethrows -> Double {
    let t = DispatchTime.now().uptimeNanoseconds
    try body()
    return Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6
}

func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }

func fileSize(_ path: String) -> Int {
    ((try? fm.attributesOfItem(atPath: path)[.size]) as? Int) ?? 0
}

/// The original behaviour: every stage renders to disk and the next stage reloads it.
/// Returns the output path and total bytes written to temp files.
func legacyChain(_ inputPath: String) throws -> (path: String, bytes: Int) {
    var written: [String] = []
    func step(_ path: String, _ prefix: String, _ f: (CIImage) throws -> CIImage) throws -> String {
        let image = ImagingIO.load(path: path)!
        let out = try ImagingIO.writeJPEG(try f(image), prefix: prefix)
        written.append(out)
        return out
    }
    let tone = try step(inputPath, "tone") { ImagingStages.toneMap($0) }
    let scene = try step(tone, "scene") { ImagingStages.sceneEnhance($0) }
    let sharp = try step(scene, "sharp") { ImagingStages.sharpen($0) }
    // Segmentation on the sharpened, reloaded image, as the old bokeh stage did.
    let final = try step(sharp, "bokeh") { try ImagingStages.bokeh($0, mask: ImagingStages.personMask(for: $0)) }
    let bytes = written.reduce(0) { $0 + fileSize($1) }
    for p in written where p != final { try? fm.removeItem(atPath: p) }
    return (final, bytes)
}

func singlePass(_ inputPath: String) throws -> (path: String, bytes: Int) {
    let out = try ImagingStages.fullPipeline(ImagingIO.load(path: inputPath)!)
    let path = try ImagingIO.writeJPEG(out, prefix: "single")
    return (path, fileSize(path))
}

func rgba(_ path: String) -> (px: [UInt8], w: Int, h: Int) {
    let img = ImagingIO.load(path: path)!
    let w = Int(img.extent.width), h = Int(img.extent.height)
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    ctx.render(img, toBitmap: &buf, rowBytes: w * 4, bounds: img.extent,
               format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    return (buf, w, h)
}

func psnr(_ a: String, _ b: String) -> Double {
    let x = rgba(a), y = rgba(b)
    guard x.w == y.w, x.h == y.h else { return .nan }
    var se = 0.0
    var n = 0
    for i in stride(from: 0, to: x.px.count, by: 4) {
        for c in 0..<3 {
            let d = Double(x.px[i + c]) - Double(y.px[i + c])
            se += d * d
            n += 1
        }
    }
    let mse = se / Double(n)
    return mse == 0 ? .infinity : 10 * log10(255 * 255 / mse)
}

func maskCoverage(_ path: String) throws -> Double {
    let img = ImagingIO.load(path: path)!
    let m = try ImagingStages.personMask(for: img)
    let avg = m.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: m.extent)])
    var px = [UInt8](repeating: 0, count: 4)
    ctx.render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
               format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    return Double(px[0]) / 255
}

func resized(_ path: String, megapixels: Double) throws -> String {
    let img = ImagingIO.load(path: path)!
    let scale = (megapixels * 1_000_000 / (img.extent.width * img.extent.height)).squareRoot()
    let scaled = img.applyingFilter("CILanczosScaleTransform", parameters: [
        kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0
    ])
    return try ImagingIO.writeJPEG(scaled, prefix: "resized")
}

print("| input | size | legacy median (min) ms | single-pass median (min) ms | speedup | of which Vision ms | temp bytes written (legacy / single) | PSNR dB | person coverage |")
print("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")

for original in inputs {
    do {
        let input = try targetMP.map { try resized(original, megapixels: $0) } ?? original
        let src = ImagingIO.load(path: input)!
        let size = "\(Int(src.extent.width))x\(Int(src.extent.height)) (\(String(format: "%.1f", src.extent.width * src.extent.height / 1e6)) MP)"

        for _ in 0..<2 { _ = try legacyChain(input); _ = try singlePass(input) }   // warm-up

        var legacyT: [Double] = [], singleT: [Double] = [], visionT: [Double] = []
        var legacyOut = "", singleOut = "", legacyBytes = 0, singleBytes = 0
        for _ in 0..<runs {
            legacyT.append(try ms { let r = try legacyChain(input); legacyOut = r.path; legacyBytes = r.bytes })
            singleT.append(try ms { let r = try singlePass(input); singleOut = r.path; singleBytes = r.bytes })
            visionT.append(try ms { _ = try ImagingStages.personMask(for: src) })
        }

        let p = psnr(legacyOut, singleOut)
        let cov = try maskCoverage(input)
        func f(_ x: Double) -> String { String(format: "%.0f", x) }
        print("| \(URL(fileURLWithPath: original).lastPathComponent) | \(size) | \(f(median(legacyT))) (\(f(legacyT.min()!))) | \(f(median(singleT))) (\(f(singleT.min()!))) | \(String(format: "%.2fx", median(legacyT) / median(singleT))) | \(f(median(visionT))) | \(legacyBytes / 1024) KB / \(singleBytes / 1024) KB | \(String(format: "%.1f", p)) | \(String(format: "%.0f%%", cov * 100)) |")

        if let keep = ProcessInfo.processInfo.environment["BENCH_KEEP_DIR"] {
            let base = URL(fileURLWithPath: original).deletingPathExtension().lastPathComponent
            try? fm.createDirectory(atPath: keep, withIntermediateDirectories: true)
            try? fm.removeItem(atPath: "\(keep)/\(base)-legacy.jpg"); try? fm.removeItem(atPath: "\(keep)/\(base)-single.jpg")
            try fm.copyItem(atPath: legacyOut, toPath: "\(keep)/\(base)-legacy.jpg")
            try fm.copyItem(atPath: singleOut, toPath: "\(keep)/\(base)-single.jpg")
        }
    } catch {
        print("| \(original) | error: \(error.localizedDescription) |")
    }
}

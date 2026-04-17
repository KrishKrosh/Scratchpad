//
//  TexoMLX.swift
//  Scratchpad
//

import Foundation
import AppKit
import CoreGraphics
import MLX
import MLXNN

enum TexoMLXError: LocalizedError {
    case missingModelDirectory(String)
    case missingFile(String)
    case invalidConfig
    case invalidTokenizer
    case missingWeight(String)
    case noStrokes
    case emptyPrediction

    var errorDescription: String? {
        switch self {
        case .missingModelDirectory(let message): return message
        case .missingFile(let file): return "Missing Texo MLX model file: \(file)"
        case .invalidConfig: return "The Texo MLX config file is invalid."
        case .invalidTokenizer: return "The Texo tokenizer file is invalid."
        case .missingWeight(let name): return "Missing converted model weight: \(name)"
        case .noStrokes: return "No selected strokes were provided for recognition."
        case .emptyPrediction: return "The model returned an empty LaTeX prediction."
        }
    }
}

struct TexoStageConfig: Codable {
    let inChannels: Int
    let midChannels: Int
    let outChannels: Int
    let blockCount: Int
    let layerCount: Int
    let kernelSize: Int
    let downsample: Bool
    let lightBlock: Bool
}

struct TexoMLXConfig: Codable {
    let imageSize: Int
    let stemChannels: [Int]
    let stages: [TexoStageConfig]
    let encoderHiddenSize: Int
    let vocabSize: Int
    let maxPositionEmbeddings: Int
    let positionOffset: Int
    let dModel: Int
    let decoderLayerCount: Int
    let decoderAttentionHeads: Int
    let decoderFFNDim: Int
    let bosTokenID: Int
    let padTokenID: Int
    let eosTokenID: Int
    let maxDecodeLength: Int
    let layerNormEps: Float
    let scaleEmbedding: Bool
}

struct TexoModelBundle {
    let directoryURL: URL
    let config: TexoMLXConfig
    let tokenizer: TexoWordLevelTokenizer
    let weights: [String: MLXArray]
}

enum TexoModelLocator {
    nonisolated static func loadBundle() throws -> TexoModelBundle {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        let repoModelPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".local/TexoMLXModel")
        let bundledModelPath = Bundle.main.resourceURL?.appendingPathComponent("TexoMLXModel", isDirectory: true)

        let candidates = [
            env["SCRATCHPAD_TEXO_MLX_MODEL"],
            repoModelPath.path,
            bundledModelPath?.path,
            "~/Library/Application Support/Scratchpad/Models/TexoMLX"
        ].compactMap { raw -> URL? in
            guard let raw else { return nil }
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        }

        guard let directoryURL = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
            throw TexoMLXError.missingModelDirectory(
                """
                Texo MLX model not found. Checked SCRATCHPAD_TEXO_MLX_MODEL, the repo-local .local/TexoMLXModel directory,
                the app bundle resources, and ~/Library/Application Support/Scratchpad/Models/TexoMLX.
                """
            )
        }

        let configURL = directoryURL.appendingPathComponent("config.json")
        let tokenizerURL = directoryURL.appendingPathComponent("tokenizer.json")
        let weightsURL = directoryURL.appendingPathComponent("weights.safetensors")

        guard fm.fileExists(atPath: configURL.path) else {
            throw TexoMLXError.missingFile(configURL.lastPathComponent)
        }
        guard fm.fileExists(atPath: tokenizerURL.path) else {
            throw TexoMLXError.missingFile(tokenizerURL.lastPathComponent)
        }
        guard fm.fileExists(atPath: weightsURL.path) else {
            throw TexoMLXError.missingFile(weightsURL.lastPathComponent)
        }

        let configData = try Data(contentsOf: configURL)
        let tokenizerData = try Data(contentsOf: tokenizerURL)
        let decoder = JSONDecoder()
        guard let config = try? decoder.decode(TexoMLXConfig.self, from: configData) else {
            throw TexoMLXError.invalidConfig
        }
        let tokenizer = try TexoWordLevelTokenizer(data: tokenizerData)
        let weights = try MLX.loadArrays(url: weightsURL)

        return TexoModelBundle(directoryURL: directoryURL, config: config, tokenizer: tokenizer, weights: weights)
    }
}

struct TexoWordLevelTokenizer {
    let idToToken: [Int: String]
    let bosTokenID: Int
    let eosTokenID: Int
    let padTokenID: Int
    let unkTokenID: Int

    init(data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let model = json?["model"] as? [String: Any],
            let vocab = model["vocab"] as? [String: Int]
        else {
            throw TexoMLXError.invalidTokenizer
        }
        self.idToToken = Dictionary(uniqueKeysWithValues: vocab.map { ($1, $0) })
        self.bosTokenID = vocab["<s>"] ?? 0
        self.padTokenID = vocab["<pad>"] ?? 1
        self.eosTokenID = vocab["</s>"] ?? 2
        self.unkTokenID = vocab["<unk>"] ?? 3
    }

    func decode(_ tokenIDs: [Int]) -> String {
        let tokens = tokenIDs.compactMap { tokenID -> String? in
            guard tokenID != bosTokenID, tokenID != eosTokenID, tokenID != padTokenID else { return nil }
            return idToToken[tokenID] ?? idToToken[unkTokenID]
        }
        return tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TexoSelectionTensorRenderer {
    private static let mean: [Float] = [0.7931, 0.7931, 0.7931]
    private static let std: [Float] = [0.1738, 0.1738, 0.1738]

    static func pixelValues(for strokes: [Stroke], imageSize: Int) throws -> MLXArray {
        let raw = try processedRGBA(for: strokes, imageSize: imageSize)
        return normalizedPixelValues(from: raw, imageSize: imageSize)
    }

    static func writeDebugPNG(for strokes: [Stroke], imageSize: Int, to url: URL) throws {
        let raw = try processedRGBA(for: strokes, imageSize: imageSize)
        try writePNG(raw: raw, width: imageSize, height: imageSize, to: url)
    }

    static func writeRawDebugPNG(for strokes: [Stroke], to url: URL) throws {
        let rasterized = try rasterizeSelection(strokes: strokes)
        try writePNG(raw: rasterized.raw, width: rasterized.width, height: rasterized.height, to: url)
    }

    private static func writePNG(raw: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard let provider = CGDataProvider(data: Data(raw) as CFData) else {
            throw TexoMLXError.invalidConfig
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw TexoMLXError.invalidConfig
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw TexoMLXError.invalidConfig
        }
        try png.write(to: url, options: .atomic)
    }

    private static func processedRGBA(for strokes: [Stroke], imageSize: Int) throws -> [UInt8] {
        let rasterized = try rasterizeSelection(strokes: strokes)
        let reversed = reverseColorIfNeeded(
            raw: rasterized.raw,
            width: rasterized.width,
            height: rasterized.height
        )
        let cropped = cropMargin(
            raw: reversed.raw,
            width: rasterized.width,
            height: rasterized.height
        )
        return try resizeAndPadToSquare(
            raw: cropped.raw,
            width: cropped.width,
            height: cropped.height,
            imageSize: imageSize
        )
    }

    private static func normalizedPixelValues(from raw: [UInt8], imageSize: Int) -> MLXArray {
        var values = [Float]()
        values.reserveCapacity(imageSize * imageSize * 3)
        for y in 0 ..< imageSize {
            for x in 0 ..< imageSize {
                let idx = (y * imageSize + x) * 4
                let gray = Float(raw[idx]) / 255.0
                for c in 0 ..< 3 {
                    values.append((gray - mean[c]) / std[c])
                }
            }
        }

        return MLXArray(values).reshaped([1, imageSize, imageSize, 3])
    }

    private static func rasterizeSelection(strokes: [Stroke]) throws -> (raw: [UInt8], width: Int, height: Int) {
        guard !strokes.isEmpty else { throw TexoMLXError.noStrokes }

        let bounds = strokes.reduce(into: CGRect.null) { partial, stroke in
            partial = partial.union(stroke.bounds)
        }.insetBy(dx: -2, dy: -2)

        let width = max(Int(ceil(bounds.width)), 1)
        let height = max(Int(ceil(bounds.height)), 1)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var raw = [UInt8](repeating: 255, count: width * height * 4)

        guard let ctx = CGContext(
            data: &raw,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TexoMLXError.invalidConfig
        }

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)

        for stroke in strokes {
            guard let first = stroke.points.first?.location else { continue }
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setLineWidth(max(stroke.width, 1))

            if stroke.points.count == 1 {
                let radius = stroke.width * 0.5
                ctx.fillEllipse(in: CGRect(x: first.x - radius, y: first.y - radius, width: radius * 2, height: radius * 2))
                continue
            }

            ctx.beginPath()
            ctx.move(to: first)
            for point in stroke.points.dropFirst() {
                ctx.addLine(to: point.location)
            }
            ctx.strokePath()
        }

        return (raw, width, height)
    }

    private static func resizeAndPadToSquare(raw: [UInt8], width: Int, height: Int, imageSize: Int) throws -> [UInt8] {
        let grayscale = grayscalePixels(from: raw, width: width, height: height)
        let scale = CGFloat(imageSize) / max(min(CGFloat(width), CGFloat(height)), 1)
        var resizedWidth = max(Int(round(CGFloat(width) * scale)), 1)
        var resizedHeight = max(Int(round(CGFloat(height) * scale)), 1)
        if resizedWidth > imageSize || resizedHeight > imageSize {
            let ratio = min(CGFloat(imageSize) / CGFloat(resizedWidth), CGFloat(imageSize) / CGFloat(resizedHeight))
            resizedWidth = max(Int(round(CGFloat(resizedWidth) * ratio)), 1)
            resizedHeight = max(Int(round(CGFloat(resizedHeight) * ratio)), 1)
        }
        let resized = resizeGrayscaleBilinear(
            pixels: grayscale,
            width: width,
            height: height,
            targetWidth: resizedWidth,
            targetHeight: resizedHeight
        )

        let offsetX = (imageSize - resizedWidth) / 2
        let offsetY = (imageSize - resizedHeight) / 2

        var output = [UInt8](repeating: 0, count: imageSize * imageSize * 4)
        for y in 0 ..< resizedHeight {
            for x in 0 ..< resizedWidth {
                let value = UInt8(max(0, min(255, Int(round(resized[y * resizedWidth + x])))))
                let dstIndex = ((y + offsetY) * imageSize + (x + offsetX)) * 4
                output[dstIndex] = value
                output[dstIndex + 1] = value
                output[dstIndex + 2] = value
                output[dstIndex + 3] = 255
            }
        }
        return output
    }

    private static func grayscalePixels(from raw: [UInt8], width: Int, height: Int) -> [Float] {
        var pixels = [Float](repeating: 255, count: width * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                pixels[y * width + x] = Float(raw[(y * width + x) * 4])
            }
        }
        return pixels
    }

    private static func resizeGrayscaleBilinear(
        pixels: [Float],
        width: Int,
        height: Int,
        targetWidth: Int,
        targetHeight: Int
    ) -> [Float] {
        var output = [Float](repeating: 0, count: targetWidth * targetHeight)
        let xScale = Float(width) / Float(targetWidth)
        let yScale = Float(height) / Float(targetHeight)

        for y in 0 ..< targetHeight {
            let sourceY = (Float(y) + 0.5) * yScale - 0.5
            let y0 = max(Int(floor(sourceY)), 0)
            let y1 = min(y0 + 1, height - 1)
            let wy = sourceY - Float(y0)

            for x in 0 ..< targetWidth {
                let sourceX = (Float(x) + 0.5) * xScale - 0.5
                let x0 = max(Int(floor(sourceX)), 0)
                let x1 = min(x0 + 1, width - 1)
                let wx = sourceX - Float(x0)

                let top = pixels[y0 * width + x0] * (1 - wx) + pixels[y0 * width + x1] * wx
                let bottom = pixels[y1 * width + x0] * (1 - wx) + pixels[y1 * width + x1] * wx
                output[y * targetWidth + x] = top * (1 - wy) + bottom * wy
            }
        }

        return output
    }

    private static func reverseColorIfNeeded(raw: [UInt8], width: Int, height: Int) -> (raw: [UInt8], width: Int, height: Int) {
        var blackPixelCount = 0
        var whitePixelCount = 0
        for y in 0 ..< height {
            for x in 0 ..< width {
                let gray = raw[(y * width + x) * 4]
                if gray < 200 {
                    blackPixelCount += 1
                } else {
                    whitePixelCount += 1
                }
            }
        }
        guard blackPixelCount >= whitePixelCount else {
            return (raw, width, height)
        }

        var inverted = raw
        for index in stride(from: 0, to: inverted.count, by: 4) {
            let value = 255 - inverted[index]
            inverted[index] = value
            inverted[index + 1] = value
            inverted[index + 2] = value
            inverted[index + 3] = 255
        }
        return (inverted, width, height)
    }

    private static func cropMargin(raw: [UInt8], width: Int, height: Int) -> (raw: [UInt8], width: Int, height: Int) {
        var minGray: UInt8 = 255
        var maxGray: UInt8 = 0
        var grays = [UInt8](repeating: 255, count: width * height)

        for y in 0 ..< height {
            for x in 0 ..< width {
                let srcIndex = (y * width + x) * 4
                let gray = raw[srcIndex]
                grays[y * width + x] = gray
                minGray = min(minGray, gray)
                maxGray = max(maxGray, gray)
            }
        }

        if minGray == maxGray {
            return (raw, width, height)
        }

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0 ..< height {
            for x in 0 ..< width {
                let gray = grays[y * width + x]
                let normalized = Int(gray) - Int(minGray)
                let scaled = normalized * 255 / max(Int(maxGray) - Int(minGray), 1)
                let isForeground = scaled < 200
                if isForeground {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return (raw, width, height)
        }

        let croppedWidth = max(maxX - minX, 1)
        let croppedHeight = max(maxY - minY, 1)
        var cropped = [UInt8](repeating: 255, count: croppedWidth * croppedHeight * 4)

        for y in 0 ..< croppedHeight {
            let srcStart = ((y + minY) * width + minX) * 4
            let dstStart = y * croppedWidth * 4
            let byteCount = croppedWidth * 4
            cropped.withUnsafeMutableBytes { dstBuffer in
                raw.withUnsafeBytes { srcBuffer in
                    let dstPtr = dstBuffer.baseAddress!.advanced(by: dstStart)
                    let srcPtr = srcBuffer.baseAddress!.advanced(by: srcStart)
                    memcpy(dstPtr, srcPtr, byteCount)
                }
            }
        }

        return (cropped, croppedWidth, croppedHeight)
    }
}

private enum TexoWeights {
    static func required(_ name: String, in weights: [String: MLXArray]) throws -> MLXArray {
        guard let value = weights[name] else {
            throw TexoMLXError.missingWeight(name)
        }
        return value
    }
}

private protocol TexoArrayLayer {
    func callAsFunction(_ x: MLXArray) -> MLXArray
}

private final class TexoConv2d {
    let weight: MLXArray
    let bias: MLXArray?
    let stride: (Int, Int)
    let padding: (Int, Int)
    let groups: Int

    init(weight: MLXArray, bias: MLXArray? = nil, stride: (Int, Int) = (1, 1), padding: (Int, Int) = (0, 0), groups: Int = 1) {
        self.weight = weight
        self.bias = bias
        self.stride = stride
        self.padding = padding
        self.groups = groups
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        if groups == 1 {
            var y = conv2d(x, weight, stride: .init(stride), padding: .init(padding))
            if let bias {
                y = y + bias
            }
            return y
        }

        let inputGroups = x.split(parts: groups, axis: 3)
        let weightGroups = weight.split(parts: groups, axis: 0)
        let biasGroups = bias?.split(parts: groups, axis: 0)

        let outputs = inputGroups.enumerated().map { index, inputGroup in
            var partial = conv2d(
                inputGroup,
                weightGroups[index],
                stride: .init(stride),
                padding: .init(padding)
            )
            if let biasGroups {
                partial = partial + biasGroups[index]
            }
            return partial
        }
        return concatenated(outputs, axis: 3)
    }
}

private final class TexoBatchNorm2d {
    let weight: MLXArray
    let bias: MLXArray
    let runningMean: MLXArray
    let runningVar: MLXArray
    let eps: Float

    init(weight: MLXArray, bias: MLXArray, runningMean: MLXArray, runningVar: MLXArray, eps: Float = 1e-5) {
        self.weight = weight
        self.bias = bias
        self.runningMean = runningMean
        self.runningVar = runningVar
        self.eps = eps
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let affineScale = weight * rsqrt(runningVar + eps)
        let scale = affineScale.reshaped([1, 1, 1, weight.shape[0]])
        let shifted = (bias - runningMean * affineScale).reshaped([
            1, 1, 1, weight.shape[0],
        ])
        return x * scale + shifted
    }
}

private final class TexoLinear {
    let weight: MLXArray
    let bias: MLXArray?

    init(weight: MLXArray, bias: MLXArray? = nil) {
        self.weight = weight
        self.bias = bias
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var y = matmul(x, weight.T)
        if let bias {
            y = y + bias
        }
        return y
    }
}

private final class TexoLayerNorm {
    let weight: MLXArray
    let bias: MLXArray
    let eps: Float

    init(weight: MLXArray, bias: MLXArray, eps: Float) {
        self.weight = weight
        self.bias = bias
        self.eps = eps
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        MLXFast.layerNorm(x, weight: weight, bias: bias, eps: eps)
    }
}

private final class TexoEmbedding {
    let weight: MLXArray

    init(weight: MLXArray) {
        self.weight = weight
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        weight[x]
    }
}

private final class TexoConvBNAct: TexoArrayLayer {
    let conv: TexoConv2d
    let bn: TexoBatchNorm2d
    let useActivation: Bool

    init(prefix: String, weights: [String: MLXArray], kernelSize: Int, stride: Int = 1, groups: Int = 1, useActivation: Bool = true) throws {
        self.conv = TexoConv2d(
            weight: try TexoWeights.required("\(prefix).conv.weight", in: weights),
            stride: (stride, stride),
            padding: ((kernelSize - 1) / 2, (kernelSize - 1) / 2),
            groups: groups
        )
        self.bn = TexoBatchNorm2d(
            weight: try TexoWeights.required("\(prefix).bn.weight", in: weights),
            bias: try TexoWeights.required("\(prefix).bn.bias", in: weights),
            runningMean: try TexoWeights.required("\(prefix).bn.running_mean", in: weights),
            runningVar: try TexoWeights.required("\(prefix).bn.running_var", in: weights)
        )
        self.useActivation = useActivation
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let y = bn(conv(x))
        return useActivation ? relu(y) : y
    }
}

private final class TexoLightConvBNAct: TexoArrayLayer {
    let conv1: TexoConvBNAct
    let conv2: TexoConvBNAct

    init(prefix: String, weights: [String: MLXArray], kernelSize: Int) throws {
        self.conv1 = try TexoConvBNAct(prefix: "\(prefix).conv1", weights: weights, kernelSize: 1, useActivation: false)
        let depthwiseChannels = try TexoWeights.required("\(prefix).conv2.bn.weight", in: weights).shape[0]
        self.conv2 = try TexoConvBNAct(prefix: "\(prefix).conv2", weights: weights, kernelSize: kernelSize, groups: depthwiseChannels)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        conv2(conv1(x))
    }
}

private final class TexoStemBlock {
    let stem1: TexoConvBNAct
    let stem2a: TexoConvBNAct
    let stem2b: TexoConvBNAct
    let stem3: TexoConvBNAct
    let stem4: TexoConvBNAct
    let pool = MaxPool2d(kernelSize: 2, stride: 1)

    init(weights: [String: MLXArray]) throws {
        self.stem1 = try TexoConvBNAct(prefix: "encoder.stem.stem1", weights: weights, kernelSize: 3, stride: 2)
        self.stem2a = try TexoConvBNAct(prefix: "encoder.stem.stem2a", weights: weights, kernelSize: 2)
        self.stem2b = try TexoConvBNAct(prefix: "encoder.stem.stem2b", weights: weights, kernelSize: 2)
        self.stem3 = try TexoConvBNAct(prefix: "encoder.stem.stem3", weights: weights, kernelSize: 3, stride: 2)
        self.stem4 = try TexoConvBNAct(prefix: "encoder.stem.stem4", weights: weights, kernelSize: 1)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let s1 = stem1(x)
        let padded1 = padded(s1, widths: [0, .init((0, 1)), .init((0, 1)), 0], mode: .constant, value: MLXArray(0.0))
        let s2a = stem2a(padded1)
        let padded2 = padded(s2a, widths: [0, .init((0, 1)), .init((0, 1)), 0], mode: .constant, value: MLXArray(0.0))
        let s2b = stem2b(padded2)
        let pooled = pool(padded1)
        let merged = concatenated([pooled, s2b], axis: 3)
        return stem4(stem3(merged))
    }
}

private final class TexoHGBlock {
    let layers: [any TexoArrayLayer]
    let aggregationSqueeze: TexoConvBNAct
    let aggregationExcitation: TexoConvBNAct
    let residual: Bool

    init(prefix: String, config: TexoStageConfig, blockIndex: Int, weights: [String: MLXArray], residual: Bool) throws {
        self.residual = residual
        var builtLayers = [any TexoArrayLayer]()
        let layerPrefixBase = "\(prefix).blocks.\(blockIndex).layers"
        for layerIndex in 0 ..< config.layerCount {
            let layerPrefix = "\(layerPrefixBase).\(layerIndex)"
            if config.lightBlock {
                builtLayers.append(try TexoLightConvBNAct(prefix: layerPrefix, weights: weights, kernelSize: config.kernelSize))
            } else {
                builtLayers.append(try TexoConvBNAct(prefix: layerPrefix, weights: weights, kernelSize: config.kernelSize))
            }
        }
        self.layers = builtLayers
        self.aggregationSqueeze = try TexoConvBNAct(
            prefix: "\(prefix).blocks.\(blockIndex).aggregation_squeeze_conv",
            weights: weights,
            kernelSize: 1
        )
        self.aggregationExcitation = try TexoConvBNAct(
            prefix: "\(prefix).blocks.\(blockIndex).aggregation_excitation_conv",
            weights: weights,
            kernelSize: 1
        )
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let identity = x
        var outputs = [x]
        var current = x
        for layer in layers {
            current = layer(current)
            outputs.append(current)
        }
        var y = concatenated(outputs, axis: 3)
        y = aggregationSqueeze(y)
        y = aggregationExcitation(y)
        return residual ? y + identity : y
    }
}

private final class TexoHGStage {
    let downsample: TexoConvBNAct?
    let blocks: [TexoHGBlock]

    init(index: Int, config: TexoStageConfig, weights: [String: MLXArray]) throws {
        let prefix = "encoder.stages.\(index)"
        if config.downsample {
            let channels = try TexoWeights.required("\(prefix).downsample.bn.weight", in: weights).shape[0]
            self.downsample = try TexoConvBNAct(
                prefix: "\(prefix).downsample",
                weights: weights,
                kernelSize: 3,
                stride: 2,
                groups: channels,
                useActivation: false
            )
        } else {
            self.downsample = nil
        }
        self.blocks = try (0 ..< config.blockCount).map { blockIndex in
            try TexoHGBlock(
                prefix: prefix,
                config: config,
                blockIndex: blockIndex,
                weights: weights,
                residual: blockIndex > 0
            )
        }
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let y = downsample?(x) ?? x
        return blocks.reduce(y) { partial, block in block(partial) }
    }
}

private final class TexoHGNetEncoder {
    let stem: TexoStemBlock
    let stages: [TexoHGStage]

    init(config: TexoMLXConfig, weights: [String: MLXArray]) throws {
        self.stem = try TexoStemBlock(weights: weights)
        self.stages = try config.stages.enumerated().map { index, stage in
            try TexoHGStage(index: index, config: stage, weights: weights)
        }
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var y = stem(x)
        for stage in stages {
            y = stage(y)
        }
        let shape = y.shape
        return y.reshaped([shape[0], shape[1] * shape[2], shape[3]])
    }
}

private final class TexoAttention {
    let qProj: TexoLinear
    let kProj: TexoLinear
    let vProj: TexoLinear
    let outProj: TexoLinear
    let headCount: Int
    let scale: Float

    init(prefix: String, headCount: Int, weights: [String: MLXArray]) throws {
        self.qProj = try TexoLinear(
            weight: TexoWeights.required("\(prefix).q_proj.weight", in: weights),
            bias: TexoWeights.required("\(prefix).q_proj.bias", in: weights)
        )
        self.kProj = try TexoLinear(
            weight: TexoWeights.required("\(prefix).k_proj.weight", in: weights),
            bias: TexoWeights.required("\(prefix).k_proj.bias", in: weights)
        )
        self.vProj = try TexoLinear(
            weight: TexoWeights.required("\(prefix).v_proj.weight", in: weights),
            bias: TexoWeights.required("\(prefix).v_proj.bias", in: weights)
        )
        self.outProj = try TexoLinear(
            weight: TexoWeights.required("\(prefix).out_proj.weight", in: weights),
            bias: TexoWeights.required("\(prefix).out_proj.bias", in: weights)
        )
        self.headCount = headCount
        let hiddenSize = try TexoWeights.required("\(prefix).q_proj.weight", in: weights).shape[0]
        self.scale = 1.0 / sqrt(Float(hiddenSize / headCount))
    }

    func callAsFunction(_ query: MLXArray, key: MLXArray, value: MLXArray, mask: MLXArray? = nil) -> MLXArray {
        let q = reshapeHeads(qProj(query))
        let k = reshapeHeads(kProj(key))
        let v = reshapeHeads(vProj(value))
        let output = MLXFast.scaledDotProductAttention(queries: q, keys: k, values: v, scale: scale, mask: mask)
        return outProj(mergeHeads(output))
    }

    private func reshapeHeads(_ x: MLXArray) -> MLXArray {
        let shape = x.shape
        let headDim = shape[2] / headCount
        return x.reshaped([shape[0], shape[1], headCount, headDim]).transposed(0, 2, 1, 3)
    }

    private func mergeHeads(_ x: MLXArray) -> MLXArray {
        let shape = x.shape
        return x.transposed(0, 2, 1, 3).reshaped([shape[0], shape[2], shape[1] * shape[3]])
    }
}

private final class TexoDecoderLayer {
    let selfAttention: TexoAttention
    let crossAttention: TexoAttention
    let selfAttentionNorm: TexoLayerNorm
    let crossAttentionNorm: TexoLayerNorm
    let finalNorm: TexoLayerNorm
    let fc1: TexoLinear
    let fc2: TexoLinear

    init(index: Int, config: TexoMLXConfig, weights: [String: MLXArray]) throws {
        let prefix = "decoder.model.decoder.layers.\(index)"
        self.selfAttention = try TexoAttention(prefix: "\(prefix).self_attn", headCount: config.decoderAttentionHeads, weights: weights)
        self.crossAttention = try TexoAttention(prefix: "\(prefix).encoder_attn", headCount: config.decoderAttentionHeads, weights: weights)
        self.selfAttentionNorm = try TexoLayerNorm(
            weight: TexoWeights.required("\(prefix).self_attn_layer_norm.weight", in: weights),
            bias: TexoWeights.required("\(prefix).self_attn_layer_norm.bias", in: weights),
            eps: config.layerNormEps
        )
        self.crossAttentionNorm = try TexoLayerNorm(
            weight: TexoWeights.required("\(prefix).encoder_attn_layer_norm.weight", in: weights),
            bias: TexoWeights.required("\(prefix).encoder_attn_layer_norm.bias", in: weights),
            eps: config.layerNormEps
        )
        self.finalNorm = try TexoLayerNorm(
            weight: TexoWeights.required("\(prefix).final_layer_norm.weight", in: weights),
            bias: TexoWeights.required("\(prefix).final_layer_norm.bias", in: weights),
            eps: config.layerNormEps
        )
        self.fc1 = try TexoLinear(
            weight: TexoWeights.required("\(prefix).fc1.weight", in: weights),
            bias: TexoWeights.required("\(prefix).fc1.bias", in: weights)
        )
        self.fc2 = try TexoLinear(
            weight: TexoWeights.required("\(prefix).fc2.weight", in: weights),
            bias: TexoWeights.required("\(prefix).fc2.bias", in: weights)
        )
    }

    func callAsFunction(_ x: MLXArray, encoderHiddenStates: MLXArray, causalMask: MLXArray) -> MLXArray {
        var y = selfAttentionNorm(x)
        y = selfAttention(y, key: y, value: y, mask: causalMask)
        var out = x + y

        y = crossAttentionNorm(out)
        y = crossAttention(y, key: encoderHiddenStates, value: encoderHiddenStates)
        out = out + y

        y = finalNorm(out)
        y = fc2(gelu(fc1(y)))
        return out + y
    }
}

private final class TexoMBartDecoder {
    let tokenEmbedding: TexoEmbedding
    let positionEmbedding: TexoEmbedding
    let embeddingNorm: TexoLayerNorm
    let finalNorm: TexoLayerNorm
    let layers: [TexoDecoderLayer]
    let lmHead: MLXArray
    let config: TexoMLXConfig

    init(config: TexoMLXConfig, weights: [String: MLXArray]) throws {
        self.config = config
        self.tokenEmbedding = try TexoEmbedding(weight: TexoWeights.required("decoder.model.decoder.embed_tokens.weight", in: weights))
        self.positionEmbedding = try TexoEmbedding(weight: TexoWeights.required("decoder.model.decoder.embed_positions.weight", in: weights))
        self.embeddingNorm = try TexoLayerNorm(
            weight: TexoWeights.required("decoder.model.decoder.layernorm_embedding.weight", in: weights),
            bias: TexoWeights.required("decoder.model.decoder.layernorm_embedding.bias", in: weights),
            eps: config.layerNormEps
        )
        self.finalNorm = try TexoLayerNorm(
            weight: TexoWeights.required("decoder.model.decoder.layer_norm.weight", in: weights),
            bias: TexoWeights.required("decoder.model.decoder.layer_norm.bias", in: weights),
            eps: config.layerNormEps
        )
        self.layers = try (0 ..< config.decoderLayerCount).map { try TexoDecoderLayer(index: $0, config: config, weights: weights) }
        self.lmHead = try TexoWeights.required("decoder.lm_head.weight", in: weights)
    }

    func generate(encoderHiddenStates: MLXArray) throws -> [Int] {
        var tokenIDs = [config.bosTokenID]

        for _ in 0 ..< config.maxDecodeLength {
            let inputIDs = MLXArray(tokenIDs.map(Int32.init)).reshaped([1, tokenIDs.count])
            let logits = forward(inputIDs: inputIDs, encoderHiddenStates: encoderHiddenStates)
            eval(logits)
            let nextToken = Int(logits[0, tokenIDs.count - 1].argMax().item(Int32.self))
            tokenIDs.append(nextToken)
            if nextToken == config.eosTokenID {
                break
            }
        }

        return tokenIDs
    }

    func logits(inputIDs tokenIDs: [Int], encoderHiddenStates: MLXArray) -> MLXArray {
        let inputIDs = MLXArray(tokenIDs.map(Int32.init)).reshaped([1, tokenIDs.count])
        let logits = forward(inputIDs: inputIDs, encoderHiddenStates: encoderHiddenStates)
        eval(logits)
        return logits
    }

    private func forward(inputIDs: MLXArray, encoderHiddenStates: MLXArray) -> MLXArray {
        var tokenEmbeds = tokenEmbedding(inputIDs)
        if config.scaleEmbedding {
            tokenEmbeds = tokenEmbeds * sqrt(Float(config.dModel))
        }
        let positions = MLXArray((0 ..< inputIDs.shape[1]).map { Int32($0 + config.positionOffset) })
            .reshaped([1, inputIDs.shape[1]])
        var x = tokenEmbeds + positionEmbedding(positions)
        x = embeddingNorm(x)

        let causalMask = createCausalMask(length: inputIDs.shape[1])
        for layer in layers {
            x = layer(x, encoderHiddenStates: encoderHiddenStates, causalMask: causalMask)
        }
        x = finalNorm(x)
        return matmul(x, lmHead.T)
    }

    private func createCausalMask(length: Int) -> MLXArray {
        let values = (0 ..< length).flatMap { row in
            (0 ..< length).map { col in col > row ? Float(-1e9) : Float(0) }
        }
        return MLXArray(values).reshaped([1, 1, length, length])
    }
}

private final class TexoFormulaNet {
    let encoder: TexoHGNetEncoder
    let encToDecProj: TexoLinear?
    let decoder: TexoMBartDecoder
    let tokenizer: TexoWordLevelTokenizer
    let config: TexoMLXConfig

    nonisolated init(bundle: TexoModelBundle) throws {
        self.config = bundle.config
        self.tokenizer = bundle.tokenizer
        self.encoder = try TexoHGNetEncoder(config: bundle.config, weights: bundle.weights)
        if let projectionWeight = bundle.weights["enc_to_dec_proj.weight"] {
            self.encToDecProj = TexoLinear(
                weight: projectionWeight,
                bias: bundle.weights["enc_to_dec_proj.bias"]
            )
        } else {
            self.encToDecProj = nil
        }
        self.decoder = try TexoMBartDecoder(config: bundle.config, weights: bundle.weights)
    }

    nonisolated func predictTokenIDs(strokes: [Stroke]) throws -> [Int] {
        let pixelValues = try TexoSelectionTensorRenderer.pixelValues(for: strokes, imageSize: config.imageSize)
        let encoded = encoder(pixelValues)
        let encoderHiddenStates = encToDecProj?(encoded) ?? encoded
        return try decoder.generate(encoderHiddenStates: encoderHiddenStates)
    }

    nonisolated func debugReport(strokes: [Stroke], prefixes: [[Int]]) throws -> [String] {
        let pixelValues = try TexoSelectionTensorRenderer.pixelValues(for: strokes, imageSize: config.imageSize)
        let encoded = encoder(pixelValues)
        let encoderHiddenStates = encToDecProj?(encoded) ?? encoded
        eval(encoderHiddenStates)

        var lines = [String]()
        lines.append("ENCODER_SHAPE=\(encoderHiddenStates.shape)")

        let flattened = encoderHiddenStates.reshaped([-1])
        let sampleCount = min(12, flattened.shape[0])
        let encoderSample = (0 ..< sampleCount).map { flattened[$0].item(Float.self) }
        lines.append("ENCODER_SAMPLE=\(encoderSample)")

        let watchedTokenIDs = [33, 279, 663, 655, 672, 681, 683]

        for prefix in prefixes {
            let logits = decoder.logits(inputIDs: prefix, encoderHiddenStates: encoderHiddenStates)
            let lastLogits = logits[0, prefix.count - 1]
            eval(lastLogits)
            let nextToken = Int(lastLogits.argMax().item(Int32.self))
            let watched = watchedTokenIDs.map { tokenID in
                "\(tokenID):\(lastLogits[tokenID].item(Float.self))"
            }
            lines.append("PREFIX=\(prefix)")
            lines.append("NEXT_TOKEN=\(nextToken)")
            lines.append("WATCHED_LOGITS=\(watched)")
        }

        return lines
    }

    nonisolated func recognize(strokes: [Stroke]) throws -> String {
        let tokenIDs = try predictTokenIDs(strokes: strokes)
        let latex = tokenizer.decode(tokenIDs)
        guard !latex.isEmpty else { throw TexoMLXError.emptyPrediction }
        return latex
    }
}

actor MLXTexoService {
    static let shared = MLXTexoService()

    private var model: TexoFormulaNet?
    private var latexCache: [Int: String] = [:]
    private var tokenCache: [Int: [Int]] = [:]

    func recognize(strokes: [Stroke]) throws -> String {
        let key = cacheKey(for: strokes)
        if let cached = latexCache[key] {
            return cached
        }
        let model = try loadedModel()

        let latex = try model.recognize(strokes: strokes)

        latexCache[key] = latex
        return latex
    }

    func predictTokenIDs(strokes: [Stroke]) throws -> [Int] {
        let key = cacheKey(for: strokes)
        if let cached = tokenCache[key] {
            return cached
        }
        let model = try loadedModel()

        let tokenIDs = try model.predictTokenIDs(strokes: strokes)

        tokenCache[key] = tokenIDs
        return tokenIDs
    }

    func debugReport(strokes: [Stroke], prefixes: [[Int]]) throws -> [String] {
        let model = try loadedModel()
        return try model.debugReport(strokes: strokes, prefixes: prefixes)
    }

    private func loadedModel() throws -> TexoFormulaNet {
        if model == nil {
            model = try TexoFormulaNet(bundle: TexoModelLocator.loadBundle())
        }
        guard let model else { throw TexoMLXError.invalidConfig }
        return model
    }

    private func cacheKey(for strokes: [Stroke]) -> Int {
        var hasher = Hasher()
        hasher.combine(strokes.count)
        for stroke in strokes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(stroke.id)
            hasher.combine(stroke.points.count)
            hasher.combine(stroke.tool.rawValue)
            hasher.combine(Int((stroke.width * 100).rounded()))
            let xs = stroke.points.map { $0.location.x }
            let ys = stroke.points.map { $0.location.y }
            let minX = xs.min() ?? 0
            let minY = ys.min() ?? 0
            let maxX = xs.max() ?? 0
            let maxY = ys.max() ?? 0
            hasher.combine(Int((minX * 10).rounded()))
            hasher.combine(Int((minY * 10).rounded()))
            hasher.combine(Int(((maxX - minX) * 10).rounded()))
            hasher.combine(Int(((maxY - minY) * 10).rounded()))
            for point in stroke.points.prefix(6) {
                hasher.combine(Int((point.location.x * 10).rounded()))
                hasher.combine(Int((point.location.y * 10).rounded()))
            }
        }
        return hasher.finalize()
    }
}

//
//  LatexRenderer.swift
//  Scratchpad
//

import Foundation
import AppKit
import WebKit

enum LatexRenderError: LocalizedError {
    case missingAssets
    case navigationFailed(String)
    case invalidMeasurement
    case snapshotFailed

    var errorDescription: String? {
        switch self {
        case .missingAssets:
            return "Bundled KaTeX assets are missing."
        case .navigationFailed(let message):
            return "KaTeX renderer failed to load: \(message)"
        case .invalidMeasurement:
            return "KaTeX returned an invalid render size."
        case .snapshotFailed:
            return "Failed to snapshot the rendered equation."
        }
    }
}

@MainActor
final class LatexRenderer {
    static let shared = LatexRenderer()

    private let cache = NSCache<NSString, NSData>()

    private init() {
        cache.countLimit = 48
    }

    func renderPNG(latex: String, color: CodableColor, displayMode: Bool = true) async throws -> (data: Data, size: CGSize) {
        let key = cacheKey(latex: latex, color: color, displayMode: displayMode)
        if let cached = cache.object(forKey: key as NSString) as Data?,
           let image = NSImage(data: cached) {
            return (cached, image.size)
        }

        let resourceRoot = try katexResourceRoot()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
        webView.setValue(false, forKey: "drawsBackground")
        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate
        webView.loadHTMLString(Self.htmlTemplate, baseURL: resourceRoot)
        try await delegate.waitForFinish()

        let cssColor = cssRGBA(color)
        let latexLiteral = try javascriptLiteral(latex)
        let colorLiteral = try javascriptLiteral(cssColor)
        let measurementSource = "window.renderEquation(\(latexLiteral), \(colorLiteral), \(displayMode ? "true" : "false"))"
        let measurementJSON = try await evaluateJavaScript(measurementSource, in: webView)

        guard
            let data = measurementJSON.data(using: .utf8),
            let measurement = try JSONSerialization.jsonObject(with: data) as? [String: Double],
            let width = measurement["width"],
            let height = measurement["height"],
            width.isFinite,
            height.isFinite
        else {
            throw LatexRenderError.invalidMeasurement
        }

        let snapshotRect = CGRect(
            x: 0,
            y: 0,
            width: max(width + 12, 24),
            height: max(height + 12, 24)
        )
        webView.frame = snapshotRect

        let configuration = WKSnapshotConfiguration()
        configuration.rect = snapshotRect
        configuration.snapshotWidth = NSNumber(value: Double(snapshotRect.width * 2))
        let image = try await snapshot(of: webView, configuration: configuration)
        guard let pngData = pngData(from: image) else {
            throw LatexRenderError.snapshotFailed
        }

        cache.setObject(pngData as NSData, forKey: key as NSString)
        return (pngData, image.size)
    }

    private func cacheKey(latex: String, color: CodableColor, displayMode: Bool) -> String {
        "\(latex)|\(color.r)|\(color.g)|\(color.b)|\(color.a)|\(displayMode)"
    }

    private func katexResourceRoot() throws -> URL {
        if let bundled = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("katex.min.js").path) {
            return bundled
        }

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let local = repoRoot.appendingPathComponent("Scratchpad/MathRenderer/Katex", isDirectory: true)
        if FileManager.default.fileExists(atPath: local.appendingPathComponent("katex.min.js").path) {
            return local
        }

        throw LatexRenderError.missingAssets
    }

    private func cssRGBA(_ color: CodableColor) -> String {
        let r = Int(max(0, min(255, round(color.r * 255))))
        let g = Int(max(0, min(255, round(color.g * 255))))
        let b = Int(max(0, min(255, round(color.b * 255))))
        return "rgba(\(r), \(g), \(b), \(color.a))"
    }

    private func javascriptLiteral(_ string: String) throws -> String {
        let data = try JSONEncoder().encode(string)
        guard let literal = String(data: data, encoding: .utf8) else {
            throw LatexRenderError.invalidMeasurement
        }
        return literal
    }

    private func evaluateJavaScript(_ source: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(source) { result, error in
                if let error {
                    continuation.resume(throwing: LatexRenderError.navigationFailed(error.localizedDescription))
                } else if let string = result as? String {
                    continuation.resume(returning: string)
                } else {
                    continuation.resume(throwing: LatexRenderError.invalidMeasurement)
                }
            }
        }
    }

    private func snapshot(of webView: WKWebView, configuration: WKSnapshotConfiguration) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: LatexRenderError.navigationFailed(error.localizedDescription))
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: LatexRenderError.snapshotFailed)
                }
            }
        }
    }

    private func pngData(from image: NSImage) -> Data? {
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static let htmlTemplate = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <link rel="stylesheet" href="katex.min.css">
      <script src="katex.min.js"></script>
      <style>
        html, body {
          margin: 0;
          padding: 0;
          background: transparent;
          overflow: hidden;
        }
        body {
          display: inline-block;
        }
        #math {
          display: inline-block;
          padding: 6px;
          background: transparent;
        }
      </style>
    </head>
    <body>
      <div id="math"></div>
      <script>
        window.renderEquation = function(latex, color, displayMode) {
          const node = document.getElementById("math");
          node.innerHTML = "";
          node.style.color = color;
          katex.render(latex, node, {
            throwOnError: false,
            strict: "ignore",
            displayMode: displayMode
          });
          const rect = node.getBoundingClientRect();
          return JSON.stringify({
            width: Math.ceil(rect.width),
            height: Math.ceil(rect.height)
          });
        };
      </script>
    </body>
    </html>
    """
}

@MainActor
private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForFinish() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: LatexRenderError.navigationFailed(error.localizedDescription))
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: LatexRenderError.navigationFailed(error.localizedDescription))
        continuation = nil
    }
}

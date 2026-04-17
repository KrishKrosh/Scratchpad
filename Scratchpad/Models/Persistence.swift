//
//  Persistence.swift
//  Scratchpad
//
//  Save / load `.scratchpad` JSON files, list the docs folder, and autosave.
//

import Foundation
import AppKit
import UniformTypeIdentifiers
import CoreGraphics

enum ScratchpadDocType {
    static let ext = "scratchpad"
    /// Declared dynamically — the app doesn't yet register a UTType. For
    /// NSSavePanel we pair this with `allowedContentTypes = [.json]` fallback.
    static let uti = UTType(filenameExtension: ext) ?? .json
}

enum Persistence {

    // MARK: - Folder layout

    /// ~/Documents/Scratchpad — where autosaved docs live.
    static var docsDirectory: URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Scratchpad", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func newAutosaveURL(title: String) -> URL {
        let safe = title.replacingOccurrences(of: "/", with: "-")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = f.string(from: Date())
        return docsDirectory
            .appendingPathComponent("\(safe)-\(stamp)")
            .appendingPathExtension(ScratchpadDocType.ext)
    }

    // MARK: - Encode / decode

    static func save(_ file: ScratchpadFile, to url: URL) throws {
        var copy = file
        copy.modifiedAt = Date()
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(copy)
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> ScratchpadFile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ScratchpadFile.self, from: data)
    }

    // MARK: - Listing

    struct DocEntry: Identifiable, Hashable {
        let id: URL
        let url: URL
        let title: String
        let modified: Date
    }

    /// All `.scratchpad` files in the docs folder, most recently modified first.
    static func list() -> [DocEntry] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: docsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let scratchpads = urls.filter { $0.pathExtension == ScratchpadDocType.ext }
        var out: [DocEntry] = []
        for url in scratchpads {
            let title: String
            if let data = try? Data(contentsOf: url),
               let f = try? JSONDecoder().decode(ScratchpadFile.self, from: data) {
                title = f.title
            } else {
                title = url.deletingPathExtension().lastPathComponent
            }
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate) ?? .distantPast
            out.append(DocEntry(id: url, url: url, title: title, modified: mod))
        }
        return out.sorted { $0.modified > $1.modified }
    }
}

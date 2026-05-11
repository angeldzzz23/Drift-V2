//
//  ModelFileEnumerator.swift
//  DriftV2 / Slipstream
//
//  Resolves a repoId → on-disk root via any registered ModelKindLoader and
//  walks it into a `[FileEntry]` manifest. Symlinks are followed (MLX's
//  HubCache uses snapshot dirs of symlinks pointing into blobs); the
//  destination peer receives plain files at the same relative paths.
//

import Foundation
import ModelKit

struct ModelFileEnumerator {
    let loaders: [any ModelKindLoader]

    /// First loader that knows where this repo lives AND has it on disk.
    /// Returns the root directory or nil if no loader has it.
    func rootURL(for repoId: String) -> URL? {
        for loader in loaders {
            guard let url = loader.localURL(repoId: repoId) else { continue }
            if loader.isDownloaded(repoId: repoId) { return url }
        }
        return nil
    }

    /// Walk `root` and emit one FileEntry per regular file. Paths are
    /// posix-style and relative to `root`. Symlinks are resolved so the
    /// destination doesn't need to reproduce the HF blob layout.
    func enumerate(at root: URL) throws -> [FileEntry] {
        let fm = FileManager.default
        var results: [FileEntry] = []
        let rootPath = root.standardizedFileURL.path

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            let resolved = fileURL.resolvingSymlinksInPath()
            let values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize else { continue }

            // Make path relative to root. Use the original (pre-resolve)
            // URL because that's the layout the destination should mirror.
            let absolute = fileURL.standardizedFileURL.path
            let relative: String
            if absolute.hasPrefix(rootPath + "/") {
                relative = String(absolute.dropFirst(rootPath.count + 1))
            } else if absolute == rootPath {
                continue
            } else {
                relative = fileURL.lastPathComponent
            }

            results.append(FileEntry(
                path: relative,
                size: UInt64(size),
                sha256: nil
            ))
        }

        return results
    }
}

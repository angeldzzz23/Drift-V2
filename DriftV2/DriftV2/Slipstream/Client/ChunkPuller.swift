//
//  ChunkPuller.swift
//  DriftV2 / Slipstream
//
//  Runs the actual file transfer against one peer: request manifest,
//  request each file's bytes, write to a staging directory, atomically
//  rename into place. Throws PullError on any unrecoverable step so the
//  caller (PeerFirstLoader) can try another peer or fall back.
//

import Foundation
import Peerly
import ModelKit

enum PullError: Error {
    case peerHasNothing
    case manifestEmpty
    case unexpectedResponse
    case sizeMismatch(path: String, expected: UInt64, got: UInt64)
    case stagingFailure(String)
}

struct ChunkPuller {
    let peerService: PeerService
    let chunkSize: Int

    /// Pull `repoId` from `peer` into `destination`. Reports cumulative
    /// bytes to `progress` (best-effort, monotonic). Uses a `.staging`
    /// sibling directory; renames atomically on success.
    @MainActor
    func pull(
        repoId: String,
        from peer: Peer,
        into destination: URL,
        progress: @escaping @Sendable (UInt64) -> Void
    ) async throws -> UInt64 {
        let client = peerService.client(of: SlipstreamContract.self, on: peer)
        let files = try await fetchManifest(repoId: repoId, client: client)
        let totalSize = files.reduce(UInt64(0)) { $0 + $1.size }

        let staging = destination
            .deletingLastPathComponent()
            .appendingPathComponent(destination.lastPathComponent + ".staging")
        try Self.prepareStaging(staging)

        var cumulative: UInt64 = 0
        for file in files {
            let outURL = staging.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: outURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let written = try await fetchFile(
                repoId: repoId,
                file: file,
                from: client,
                writingTo: outURL,
                baseProgress: cumulative,
                progress: progress
            )
            guard written == file.size else {
                throw PullError.sizeMismatch(path: file.path, expected: file.size, got: written)
            }
            cumulative &+= written
        }

        try Self.commit(staging: staging, into: destination)
        return totalSize
    }

    // MARK: - Steps

    @MainActor
    private func fetchManifest(
        repoId: String,
        client: ServiceClient<SlipstreamContract>
    ) async throws -> [FileEntry] {
        let stream = client.stream(.manifest(repoId: repoId))
        for try await response in stream {
            switch response {
            case .manifest(let files):
                if files.isEmpty { throw PullError.peerHasNothing }
                return files
            case .bytes, .notHave:
                throw PullError.unexpectedResponse
            }
        }
        throw PullError.manifestEmpty
    }

    @MainActor
    private func fetchFile(
        repoId: String,
        file: FileEntry,
        from client: ServiceClient<SlipstreamContract>,
        writingTo url: URL,
        baseProgress: UInt64,
        progress: @escaping @Sendable (UInt64) -> Void
    ) async throws -> UInt64 {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let stream = client.stream(.fetch(
            repoId: repoId,
            path: file.path,
            offset: 0,
            length: file.size
        ))
        var written: UInt64 = 0
        for try await response in stream {
            switch response {
            case .bytes(_, let data):
                try handle.write(contentsOf: data)
                written &+= UInt64(data.count)
                progress(baseProgress &+ written)
            case .notHave:
                throw PullError.peerHasNothing
            case .manifest:
                throw PullError.unexpectedResponse
            }
        }
        return written
    }

    // MARK: - Staging

    private static func prepareStaging(_ url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func commit(staging: URL, into destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fm.fileExists(atPath: destination.path) {
            // Earlier (partial) download — wipe to leave a clean tree.
            try fm.removeItem(at: destination)
        }
        do {
            try fm.moveItem(at: staging, to: destination)
        } catch {
            throw PullError.stagingFailure(error.localizedDescription)
        }
    }
}

//
//  PeerFirstLoader.swift
//  DriftV2 / Slipstream
//
//  A `ModelKindLoader` decorator. Wraps a concrete loader (MLX, Whisper)
//  and steers `startDownload` through peers first, falling back to the
//  wrapped loader (HuggingFace) on miss/failure. All other methods pass
//  through unchanged — `isDownloaded`, `load`, `delete`, `localURL`.
//
//  Behavior is gated by `SlipstreamConfig.mode`:
//   - .peerFirstThenUpstream → try peers, fall through on miss
//   - .peerOnly              → try peers, fail if none worked (benchmark)
//   - .upstreamOnly          → bypass; direct call to wrapped loader
//

import Foundation
import Peerly
import ModelKit

public struct PeerFirstLoader: ModelKindLoader {
    public let kind: ModelKind
    let wrapped: any ModelKindLoader
    let peerService: PeerService
    let config: SlipstreamConfig
    let gate: DownloadGate
    let emit: @Sendable (SlipstreamEvent) -> Void

    init(
        wrapping loader: any ModelKindLoader,
        peerService: PeerService,
        config: SlipstreamConfig,
        gate: DownloadGate,
        emit: @escaping @Sendable (SlipstreamEvent) -> Void
    ) {
        self.kind = loader.kind
        self.wrapped = loader
        self.peerService = peerService
        self.config = config
        self.gate = gate
        self.emit = emit
    }

    // MARK: - Pass-throughs

    public func isDownloaded(repoId: String) -> Bool {
        wrapped.isDownloaded(repoId: repoId)
    }

    public func localURL(repoId: String) -> URL? {
        wrapped.localURL(repoId: repoId)
    }

    public func load(
        repoId: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> any LoadedModel {
        try await wrapped.load(repoId: repoId, progressHandler: progressHandler)
    }

    public func delete(repoId: String) {
        wrapped.delete(repoId: repoId)
    }

    // MARK: - Steered download

    public func startDownload(
        repoId: String,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        // Capture self into Sendable locals before the @Sendable closure
        // — PeerFirstLoader's stored properties are all Sendable, but the
        // compiler can't always prove that through `self.x` in a closure.
        let wrapped = self.wrapped
        let peerService = self.peerService
        let config = self.config
        let emit = self.emit
        let pull: @Sendable (Peer, String, Int, @escaping @Sendable (Double) -> Void) async throws -> UInt64 = {
            peer, repoId, chunkSize, progressHandler in
            try await Self.pullFromPeer(
                peer: peer,
                repoId: repoId,
                chunkSize: chunkSize,
                wrapped: wrapped,
                peerService: peerService,
                emit: emit,
                progressHandler: progressHandler
            )
        }
        let diskBytes: @Sendable (String) async -> UInt64 = { repoId in
            await Self.diskBytes(for: repoId, wrapped: wrapped)
        }

        try await gate.withSlot {
            let mode = await MainActor.run { config.mode }
            let chunkSize = await MainActor.run { config.chunkSize }
            let started = Date()

            if mode == .upstreamOnly {
                emit(.downloadStarted(repoId: repoId, source: .upstream, expectedBytes: nil))
                try await wrapped.startDownload(repoId: repoId, progressHandler: progressHandler)
                emit(.downloadFinished(
                    repoId: repoId,
                    source: .upstream,
                    bytes: await diskBytes(repoId),
                    wallTime: Date().timeIntervalSince(started)
                ))
                return
            }

            let candidates = await MainActor.run {
                PeerSourceSelector(peerService: peerService).candidates(for: repoId)
            }

            for peer in candidates {
                do {
                    let bytes = try await pull(peer, repoId, chunkSize, progressHandler)
                    emit(.downloadFinished(
                        repoId: repoId,
                        source: .peer(name: peer.displayName),
                        bytes: bytes,
                        wallTime: Date().timeIntervalSince(started)
                    ))
                    return
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    emit(.peerFailed(
                        repoId: repoId,
                        peer: peer.displayName,
                        reason: String(describing: error)
                    ))
                    continue
                }
            }

            if mode == .peerOnly {
                let reason = candidates.isEmpty
                    ? "no peers advertise this model"
                    : "every candidate peer failed"
                emit(.downloadFailed(repoId: repoId, reason: reason))
                throw NoPeerSourceError(reason: reason)
            }

            // peerFirstThenUpstream: fall through to HF.
            emit(.downloadStarted(repoId: repoId, source: .upstream, expectedBytes: nil))
            try await wrapped.startDownload(repoId: repoId, progressHandler: progressHandler)
            emit(.downloadFinished(
                repoId: repoId,
                source: .upstream,
                bytes: await diskBytes(repoId),
                wallTime: Date().timeIntervalSince(started)
            ))
        }
    }

    // MARK: - Helpers

    @MainActor
    private static func pullFromPeer(
        peer: Peer,
        repoId: String,
        chunkSize: Int,
        wrapped: any ModelKindLoader,
        peerService: PeerService,
        emit: @escaping @Sendable (SlipstreamEvent) -> Void,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> UInt64 {
        guard let destination = wrapped.localURL(repoId: repoId) else {
            throw PullError.peerHasNothing
        }

        emit(.downloadStarted(repoId: repoId, source: .peer(name: peer.displayName), expectedBytes: nil))

        let puller = ChunkPuller(peerService: peerService, chunkSize: chunkSize)
        let repoIdCopy = repoId
        let bytes = try await puller.pull(
            repoId: repoId,
            from: peer,
            into: destination,
            progress: { cumulative in
                emit(.progress(repoId: repoIdCopy, bytes: cumulative, of: nil))
                // We don't know total bytes until manifest lands — feed an
                // unknowable fraction by clamping at 0.99 until commit.
                progressHandler(min(0.99, Double(cumulative) / Double(max(cumulative + 1, 1))))
            }
        )
        progressHandler(1.0)
        return bytes
    }

    private static func diskBytes(for repoId: String, wrapped: any ModelKindLoader) async -> UInt64 {
        guard let url = wrapped.localURL(repoId: repoId) else { return 0 }
        return directorySize(url) ?? 0
    }

    private static func directorySize(_ url: URL) -> UInt64? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            let resolved = fileURL.resolvingSymlinksInPath()
            let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true, let size = values?.fileSize {
                total &+= UInt64(size)
            }
        }
        return total
    }
}

public struct NoPeerSourceError: Error, LocalizedError {
    public let reason: String
    public var errorDescription: String? { "No peer source: \(reason)" }
}

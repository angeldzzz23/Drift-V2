//
//  SlipstreamService.swift
//  DriftV2 / Slipstream
//
//  Host side. Implements `SlipstreamContract` over Peerly: replies to
//  `.manifest` with a file list, streams bytes for `.fetch`. Stateless
//  per request; cancellation propagates via the AsyncThrowingStream task.
//

import Foundation
import Peerly
import ModelKit

@MainActor
final class SlipstreamService: Service {
    typealias Contract = SlipstreamContract

    private let enumerator: ModelFileEnumerator
    private let config: SlipstreamConfig
    private let emit: @Sendable (SlipstreamEvent) -> Void

    init(
        loaders: [any ModelKindLoader],
        config: SlipstreamConfig,
        emit: @escaping @Sendable (SlipstreamEvent) -> Void
    ) {
        self.enumerator = ModelFileEnumerator(loaders: loaders)
        self.config = config
        self.emit = emit
    }

    /// Advertised to peers in `hello`. Lets a peer skip us cheaply when we
    /// have weights but aren't sharing them.
    var metadata: [String: String] {
        ["sharesWeights": config.sharesWeights ? "true" : "false"]
    }

    func handle(
        _ request: SlipstreamRequest,
        context: ServiceCallContext
    ) -> AsyncThrowingStream<SlipstreamResponse, Error> {
        let sharesWeights = config.sharesWeights
        let chunkSize = config.chunkSize
        let enumerator = self.enumerator

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if !sharesWeights {
                        // Polite no: empty manifest tells the caller to move on.
                        if case .manifest = request {
                            continuation.yield(.manifest(files: []))
                        } else {
                            continuation.yield(.notHave)
                        }
                        continuation.finish()
                        return
                    }

                    switch request {
                    case .manifest(let repoId):
                        guard let root = await MainActor.run(body: { enumerator.rootURL(for: repoId) }) else {
                            continuation.yield(.manifest(files: []))
                            continuation.finish()
                            return
                        }
                        let files = try enumerator.enumerate(at: root)
                        continuation.yield(.manifest(files: files))
                        continuation.finish()

                    case .fetch(let repoId, let path, let offset, let length):
                        guard let root = await MainActor.run(body: { enumerator.rootURL(for: repoId) }) else {
                            continuation.yield(.notHave)
                            continuation.finish()
                            return
                        }
                        let fileURL = root.appendingPathComponent(path).resolvingSymlinksInPath()
                        guard FileManager.default.fileExists(atPath: fileURL.path) else {
                            continuation.yield(.notHave)
                            continuation.finish()
                            return
                        }
                        try Self.stream(
                            from: fileURL,
                            offset: offset,
                            length: length,
                            chunkSize: chunkSize,
                            continuation: continuation
                        )
                        continuation.finish()
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func stream(
        from url: URL,
        offset: UInt64,
        length: UInt64,
        chunkSize: Int,
        continuation: AsyncThrowingStream<SlipstreamResponse, Error>.Continuation
    ) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: offset)
        var remaining = length
        var cursor = offset

        while remaining > 0 {
            try Task.checkCancellation()
            let want = Int(min(UInt64(chunkSize), remaining))
            let data = try handle.read(upToCount: want) ?? Data()
            if data.isEmpty { break }
            continuation.yield(.bytes(offset: cursor, data: data))
            cursor &+= UInt64(data.count)
            remaining &-= UInt64(data.count)
        }
    }
}

//
//  SlipstreamRecorder.swift
//  DriftV2 / Slipstream
//
//  Ring buffer of completed downloads. The thing you actually read for the
//  A/B comparison: "Mistral-7B from Sarah's iPad: 51s @ 80 MB/s" vs
//  "Mistral-7B from HuggingFace: 6m 12s @ 11 MB/s".
//

import Foundation
import Observation

@Observable
@MainActor
public final class SlipstreamRecorder {
    public struct Entry: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let repoId: String
        public let source: SlipstreamEvent.Source
        public let bytes: UInt64
        public let wallTime: TimeInterval
        public let finishedAt: Date

        public var mbPerSecond: Double {
            guard wallTime > 0 else { return 0 }
            return (Double(bytes) / wallTime) / 1_000_000
        }
    }

    public private(set) var entries: [Entry] = []
    private let capacity: Int

    public init(capacity: Int = 64) {
        self.capacity = capacity
    }

    public func record(_ event: SlipstreamEvent) {
        guard case .downloadFinished(let repoId, let source, let bytes, let wall) = event else {
            return
        }
        let entry = Entry(
            id: UUID(),
            repoId: repoId,
            source: source,
            bytes: bytes,
            wallTime: wall,
            finishedAt: Date()
        )
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    public func clear() { entries.removeAll() }
}

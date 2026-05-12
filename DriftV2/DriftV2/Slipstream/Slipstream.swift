//
//  Slipstream.swift
//  DriftV2 / Slipstream
//
//  Public façade. The only entry point the app needs.
//
//  ```swift
//  let raw: [any ModelKindLoader] = [llmLoader, vlmLoader, whisperLoader]
//  let mesh = Slipstream.install(
//      into: registry,
//      loaders: raw,
//      peerService: peer,
//      config: SlipstreamConfig()
//  )
//  // mesh.events is an AsyncStream<SlipstreamEvent> for UI/metrics.
//  ```
//
//  Everything else in this folder is internal to the module. When the
//  time comes to extract into a Swift package, `git mv` the folder and
//  add a Package.swift — no other edits required.
//

import Foundation
import Peerly
import ModelKit

public struct Slipstream: Sendable {
    /// Live event stream. Hot — multiple subscribers fan out from the
    /// underlying continuation. Use for UI labels and benchmark recording.
    public let events: AsyncStream<SlipstreamEvent>

    /// Host-side reference. Held by the app so it can re-register on
    /// config changes (e.g., when the user toggles `sharesWeights`).
    public let fetchService: AnyObject

    @MainActor
    public static func install(
        into registry: ModelKindRegistry,
        loaders: [any ModelKindLoader],
        peerService: PeerService,
        config: SlipstreamConfig
    ) -> Slipstream {
        let (stream, continuation) = AsyncStream<SlipstreamEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(256)
        )
        let emit: @Sendable (SlipstreamEvent) -> Void = { continuation.yield($0) }

        // Shared across every PeerFirstLoader — the cap is global across
        // model kinds, not per-loader.
        let gate = DownloadGate(capacity: config.maxConcurrentDownloads)

        // Client side: wrap each raw loader and register the wrapper into
        // the registry the app's ModelStore consults.
        for loader in loaders {
            let wrapped = PeerFirstLoader(
                wrapping: loader,
                peerService: peerService,
                config: config,
                gate: gate,
                emit: emit
            )
            registry.register(wrapped)
        }

        // Host side: register the file-fetch service. Uses the same raw
        // loaders (NOT the decorators) for enumeration — we serve from
        // local disk, never via the peer path.
        let service = SlipstreamService(
            loaders: loaders,
            config: config,
            emit: emit
        )
        peerService.register(service)

        return Slipstream(events: stream, fetchService: service)
    }
}

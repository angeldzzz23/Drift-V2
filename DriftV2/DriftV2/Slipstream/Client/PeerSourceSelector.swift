//
//  PeerSourceSelector.swift
//  DriftV2 / Slipstream
//
//  Reads `PeerService.peerHellos` and figures out which connected peers
//  claim to have a given `repoId` on disk. v1 ranks by no signal beyond
//  "connected" — v2 can prefer by latency, RAM, or `busy=false`.
//

import Foundation
import Peerly

@MainActor
struct PeerSourceSelector {
    let peerService: PeerService

    /// Connected peers that advertise `repoId` with status `idle | loading
    /// | loaded` AND that have `sharesWeights != "false"` on their fetch
    /// service. Order is unspecified beyond "non-busy peers first."
    func candidates(for repoId: String) -> [Peer] {
        var nonBusy: [Peer] = []
        var busy: [Peer] = []

        for peer in peerService.connectedPeers {
            guard let hello = peerService.peerHellos[peer.id] else { continue }
            guard Self.advertises(repoId: repoId, in: hello.services) else { continue }
            guard Self.willShareWeights(in: hello.services) else { continue }
            if hello.busy {
                busy.append(peer)
            } else {
                nonBusy.append(peer)
            }
        }
        return nonBusy + busy
    }

    /// Look at every service the peer offers and scan its `metadata["models"]`
    /// for our repoId. We don't care which service kind advertises it — if
    /// any does, the peer has the bytes.
    private static func advertises(repoId: String, in services: [ServiceCapability]) -> Bool {
        for service in services {
            guard let json = service.metadata["models"],
                  let data = json.data(using: .utf8),
                  let models = try? JSONDecoder().decode([AdvertisedModel].self, from: data)
            else { continue }
            if models.contains(where: { $0.id == repoId }) {
                return true
            }
        }
        return false
    }

    /// If the peer advertises the Slipstream service, respect its
    /// `sharesWeights` flag. If it doesn't advertise the service at all,
    /// it can't serve us — also skip.
    private static func willShareWeights(in services: [ServiceCapability]) -> Bool {
        guard let slipstream = services.first(where: { $0.id == SlipstreamContract.id }) else {
            return false
        }
        return slipstream.metadata["sharesWeights"] != "false"
    }

    /// Minimal mirror of DriftV2.ServiceModelInfo's wire shape so this
    /// module doesn't depend on the app's Routing types. Decoding only.
    private struct AdvertisedModel: Decodable {
        let id: String
    }
}

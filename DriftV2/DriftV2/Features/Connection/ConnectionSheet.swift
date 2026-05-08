//
//  ConnectionSheet.swift
//  DriftV2
//

import SwiftUI
import Peerly

struct ConnectionSheet: View {
    @Environment(PeerService.self) private var peerService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("This device") {
                    DeviceCard(
                        title: peerService.myPeer.displayName,
                        subtitle: "Local",
                        profile: peerService.myProfile
                    )
                    ServicesView(services: peerService.advertisedServices, source: .local)
                }

                if !peerService.connectedPeers.isEmpty {
                    Section("Connected") {
                        ForEach(peerService.connectedPeers) { peer in
                            connectedRow(for: peer)
                        }
                    }
                }

                Section {
                    if peerService.availablePeers.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Searching for nearby devices…")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(peerService.availablePeers) { peer in
                            availableRow(for: peer)
                        }
                    }
                } header: {
                    Text("Available")
                } footer: {
                    Text("Devices on the same Wi-Fi running DriftV2 will appear here.")
                }
            }
            .listStyle(.inset)
            .navigationTitle("Connections")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if DEBUG
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dumpServicesAndStatus()
                    } label: {
                        Label("Print", systemImage: "ladybug")
                    }
                }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 540, idealHeight: 640)
        #endif
    }

    @ViewBuilder
    private func connectedRow(for peer: Peer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DeviceCard(
                title: peer.displayName,
                subtitle: peerService.peerHellos[peer.id]?.profile?.summary,
                profile: peerService.peerHellos[peer.id]?.profile
            )
            if let hello = peerService.peerHellos[peer.id] {
                ServicesView(services: hello.services, source: .remote(peer))
            }
            HStack {
                Spacer()
                Button(role: .destructive) {
                    peerService.disconnect(peer: peer)
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func availableRow(for peer: Peer) -> some View {
        let state = peerService.connectionState(for: peer)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName).font(.headline)
                if let services = peerService.peerHellos[peer.id]?.services, !services.isEmpty {
                    Text(services.map(\.id).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
            connectButton(for: peer, state: state)
        }
        .padding(.vertical, 4)
    }

    /// Curated key order for readable metadata dumps. Anything not listed
    /// falls to alphabetical order at the end.
    private static let metadataKeyOrder = ["type", "status", "models"]

    private func printMetadata(_ metadata: [String: String], indent: String) {
        let known = Self.metadataKeyOrder.filter { metadata[$0] != nil }
        let rest = metadata.keys
            .filter { !Self.metadataKeyOrder.contains($0) }
            .sorted()
        for key in known + rest {
            guard let value = metadata[key] else { continue }
            if let pretty = prettyJSON(value) {
                print("\(indent)\(key) =")
                for line in pretty.split(separator: "\n", omittingEmptySubsequences: false) {
                    print("\(indent)  \(line)")
                }
            } else {
                print("\(indent)\(key) = \(value)")
            }
        }
    }

    private func prettyJSON(_ s: String) -> String? {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: obj,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let str = String(data: pretty, encoding: .utf8)
        else { return nil }
        return str
    }

    private func dumpServicesAndStatus() {
        print("=== Local services (\(peerService.myPeer.displayName)) ===")
        if peerService.advertisedServices.isEmpty {
            print("  (none)")
        }
        for service in peerService.advertisedServices {
            print("  \(service.id)")
            printMetadata(service.metadata, indent: "    ")
        }

        print("=== Connected peers ===")
        if peerService.connectedPeers.isEmpty {
            print("  (none)")
        }
        for peer in peerService.connectedPeers {
            print("  [\(peer.displayName)]")
            guard let hello = peerService.peerHellos[peer.id] else {
                print("    (no hello yet)")
                continue
            }
            if hello.services.isEmpty {
                print("    (no services)")
            }
            for service in hello.services {
                print("    \(service.id)")
                printMetadata(service.metadata, indent: "      ")
            }
        }
    }

    @ViewBuilder
    private func `connectButton`(for peer: Peer, state: PeerConnectionState) -> some View {
        switch state {
        case .notConnected:
            Button("Connect") {
                peerService.connect(to: peer)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .connecting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Connecting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

#Preview {
    ConnectionSheet()
        .environment(PeerService())
        .environment(BackendSelection())
}

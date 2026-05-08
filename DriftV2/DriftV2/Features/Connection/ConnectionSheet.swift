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
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dumpServicesAndStatus()
                    } label: {
                        Label("Print", systemImage: "ladybug")
                    }
                }
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

    private func dumpServicesAndStatus() {
        print("=== Local services (\(peerService.myPeer.displayName)) ===")
        if peerService.advertisedServices.isEmpty {
            print("  (none)")
        }
        
        // this collect will print 
        for service in peerService.advertisedServices {
            print("  \(service.id)")
            for (k, v) in service.metadata.sorted(by: { $0.key < $1.key }) {
                print("    \(k) = \(v)")
            }
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
                for (k, v) in service.metadata.sorted(by: { $0.key < $1.key }) {
                    print("      \(k) = \(v)")
                }
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
}

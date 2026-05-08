//
//  HostActivityView.swift
//  DriftV2
//
//  Sheet showing service calls THIS device is currently serving (or has
//  recently served). Streams chunks live as they're generated.
//

import SwiftUI

struct HostActivityView: View {
    @Environment(HostActivityLog.self) private var log
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if log.sessions.isEmpty {
                    ContentUnavailableView(
                        "No remote activity",
                        systemImage: "server.rack",
                        description: Text("When another device uses this one as a backend, requests will stream here.")
                    )
                } else {
                    List {
                        ForEach(log.sessions.reversed()) { session in
                            HostSessionRow(session: session)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Hosted activity")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .destructive) {
                        log.clear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(log.sessions.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 620, minHeight: 540, idealHeight: 720)
        #endif
    }
}

private struct HostSessionRow: View {
    let session: HostSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusIcon
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.peerName).font(.subheadline.weight(.semibold))
                    Text(session.serviceID)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(session.startedAt, format: .dateTime.hour().minute().second())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Prompt")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(session.prompt.isEmpty ? "(no prompt)" : session.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if !session.accumulated.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Generated")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(session.accumulated.count) chars")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(session.accumulated)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if case .failed(let message) = session.status {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch session.status {
        case .running:
            ProgressView().controlSize(.small)
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .cancelled:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    HostActivityView()
        .environment(HostActivityLog())
}

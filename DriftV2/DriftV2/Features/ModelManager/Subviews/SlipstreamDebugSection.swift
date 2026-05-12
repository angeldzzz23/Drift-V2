//
//  SlipstreamDebugSection.swift
//  DriftV2
//
//  A/B controls for the peer-vs-upstream model fetch path. Sits at the top
//  of the Models list. Renders:
//   - mode picker (peerFirstThenUpstream / peerOnly / upstreamOnly)
//   - "share my models with peers" toggle
//   - rolling table of recent transfers (source, size, wall time, MB/s)
//

import SwiftUI

struct SlipstreamDebugSection: View {
    @Environment(SlipstreamConfig.self) private var config
    @Environment(SlipstreamRecorder.self) private var recorder

    var body: some View {
        @Bindable var config = config

        Section("Slipstream source") {
            Picker("Mode", selection: $config.mode) {
                ForEach(SlipstreamConfig.Mode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .onChange(of: config.mode) { _, _ in config.persist() }

            Toggle("Share my models with peers", isOn: $config.sharesWeights)
                .onChange(of: config.sharesWeights) { _, _ in config.persist() }
        }

        if !recorder.entries.isEmpty {
            Section("Recent transfers") {
                ForEach(recorder.entries.reversed()) { entry in
                    TransferRow(entry: entry)
                }
                Button("Clear", role: .destructive) { recorder.clear() }
            }
        }
    }
}

private struct TransferRow: View {
    let entry: SlipstreamRecorder.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(repoTail)
                    .font(.subheadline.monospaced())
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Text(sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text(sizeLabel).font(.caption).foregroundStyle(.secondary)
                Text(timeLabel).font(.caption).foregroundStyle(.secondary)
                Text(rateLabel).font(.caption.weight(.semibold))
                    .foregroundStyle(entry.source == .upstream ? Color.secondary : Color.green)
            }
        }
    }

    private var repoTail: String {
        entry.repoId.split(separator: "/").last.map(String.init) ?? entry.repoId
    }

    private var sourceLabel: String {
        switch entry.source {
        case .peer(let name): return "via \(name)"
        case .upstream:       return "upstream"
        }
    }

    private var sizeLabel: String {
        let mb = Double(entry.bytes) / 1_000_000
        if mb >= 1000 { return String(format: "%.1f GB", mb / 1000) }
        return String(format: "%.0f MB", mb)
    }

    private var timeLabel: String {
        let t = entry.wallTime
        if t >= 60 { return String(format: "%dm %02ds", Int(t) / 60, Int(t) % 60) }
        return String(format: "%.1fs", t)
    }

    private var rateLabel: String {
        String(format: "%.1f MB/s", entry.mbPerSecond)
    }
}

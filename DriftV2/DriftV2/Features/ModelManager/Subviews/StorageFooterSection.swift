//
//  StorageFooterSection.swift
//  DriftV2
//

import SwiftUI

struct StorageFooterSection: View {
    let root: URL
    let diskRevision: Int

    var body: some View {
        Section("Storage") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "externaldrive").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("On disk").font(.headline)
                    Text(usageString).font(.subheadline).foregroundStyle(.secondary)
                    Text(root.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            .padding(.vertical, 4)
        }
        .id(diskRevision)
    }

    private var usageString: String {
        ByteCountFormatter.string(fromByteCount: diskUsage(at: root), countStyle: .file)
    }

    private func diskUsage(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}

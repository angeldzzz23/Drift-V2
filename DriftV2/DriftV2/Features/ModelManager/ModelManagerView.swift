//
//  ModelManagerView.swift
//  DriftV2
//

import SwiftUI
import ModelKit

struct ModelManagerView: View {
    @State private var vm: ModelManagerViewModel
    /// Guards `.task` against re-firing on every tab switch. Modern
    /// TabView preserves `@State` across tab visits, so this stays true
    /// for the rest of the session once defaults have been kicked off.
    @State private var didLoadDefaults = false

    init(store: ModelStore) {
        _vm = State(initialValue: ModelManagerViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DeviceSummaryRow(summary: vm.deviceSummary, tier: vm.deviceTier)
                }

                ForEach(vm.groupedCatalog, id: \.0) { kind, entries in
                    Section(kind.label) {
                        ForEach(entries) { entry in
                            ModelRow(
                                entry: entry,
                                state: vm.rowState(for: entry),
                                isDefault: vm.isDefault(entry),
                                onDownload: { vm.requestDownload(entry) },
                                onCancel: { vm.cancelDownload(entry) },
                                onLoad: { Task { await vm.load(entry) } },
                                onUnload: { vm.unload(entry) },
                                onDelete: { vm.requestDelete(entry) },
                                onToggleDefault: { vm.toggleDefault(entry) }
                            )
                        }
                    }
                }

                StorageFooterSection(root: vm.storageRoot, diskRevision: vm.diskRevision)
            }
            .navigationTitle("Models")
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .task {
                guard !didLoadDefaults else { return }
                didLoadDefaults = true
                await vm.loadDefaults()
            }
            .alert(
                "Delete model?",
                isPresented: Binding(
                    get: { vm.entryToDelete != nil },
                    set: { if !$0 { vm.entryToDelete = nil } }
                ),
                presenting: vm.entryToDelete
            ) { _ in
                Button("Delete", role: .destructive) { vm.confirmDelete() }
                Button("Cancel", role: .cancel) { vm.entryToDelete = nil }
            } message: { entry in
                Text("This removes \(entry.displayName) (\(ModelManagerViewModel.formatGB(entry.approxSizeGB))) from disk.")
            }
            .alert(
                "Device may not have enough memory",
                isPresented: Binding(
                    get: { vm.compatibilityWarning != nil },
                    set: { if !$0 { vm.compatibilityWarning = nil } }
                ),
                presenting: vm.compatibilityWarning
            ) { _ in
                Button("Download anyway") { vm.confirmDownloadAnyway() }
                Button("Cancel", role: .cancel) { vm.compatibilityWarning = nil }
            } message: { entry in
                Text("\(entry.displayName) recommends \(entry.minTier.label). This device is \(vm.deviceSummary).")
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { vm.lastError != nil },
                    set: { if !$0 { vm.clearError() } }
                ),
                presenting: vm.lastError
            ) { _ in
                Button("OK") { vm.clearError() }
            } message: { msg in
                Text(msg)
            }
        }
    }
}

#Preview {
    ModelManagerView(store: ModelStore(registry: ModelKindRegistry()))
}

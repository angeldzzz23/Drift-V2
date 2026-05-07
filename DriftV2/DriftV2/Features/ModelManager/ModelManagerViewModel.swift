//
//  ModelManagerViewModel.swift
//  DriftV2
//

import Foundation
import Observation
import os
import ModelKit

/// Single source of truth for what to render in a row — collapses the
/// download/load/loaded boolean matrix into one value.
enum ModelRowState: Equatable {
    case notDownloaded(compatible: Bool)
    case downloading(progress: Double)
    case onDisk
    case loading
    case loaded
}

@Observable
@MainActor
final class ModelManagerViewModel {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DriftV2",
        category: "ModelManager"
    )

    /// UserDefaults key for the persisted set of default-model entry.ids.
    private static let defaultsKey = "DriftV2.defaultModelEntryIds"

    private let store: ModelStore

    var entryToDelete: ModelEntry?
    var compatibilityWarning: ModelEntry?

    init(store: ModelStore) {
        self.store = store
        hydrateDefaultsFromUserDefaults()
    }

    // MARK: - Read-through projections

    var groupedCatalog: [(ModelKind, [ModelEntry])] { Catalog.grouped() }

    var deviceSummary: String { Device.summary }
    var deviceTier: DeviceTier { Device.currentTier }

    var diskRevision: Int { store.diskRevision }
    var storageRoot: URL { ModelStorage.root }

    var lastError: String? { store.lastError }
    func clearError() { store.clearError() }

    func rowState(for entry: ModelEntry) -> ModelRowState {
        if store.isLoaded(entry) { return .loaded }
        if store.isLoading(entry) { return .loading }
        if store.isDownloading(entry) {
            return .downloading(progress: store.progress(for: entry) ?? 0)
        }
        if store.isDownloaded(entry) { return .onDisk }
        return .notDownloaded(compatible: deviceTier >= entry.minTier)
    }

    func isDefault(_ entry: ModelEntry) -> Bool {
        store.defaults.contains(entry)
    }

    // MARK: - Actions

    func requestDownload(_ entry: ModelEntry) {
        if deviceTier >= entry.minTier {
            Self.logger.info("Begin download: \(entry.repoId, privacy: .public)")
            store.startDownload(entry)
            watchDownloadCompletion(entry)
        } else {
            Self.logger.info("Compatibility warning shown: \(entry.repoId, privacy: .public) (needs \(entry.minTier.label, privacy: .public), device is \(Device.summary, privacy: .public))")
            compatibilityWarning = entry
        }
    }

    func confirmDownloadAnyway() {
        guard let entry = compatibilityWarning else { return }
        Self.logger.info("Begin download (override): \(entry.repoId, privacy: .public)")
        store.startDownload(entry)
        watchDownloadCompletion(entry)
        compatibilityWarning = nil
    }

    func cancelDownload(_ entry: ModelEntry) {
        Self.logger.info("Cancel download: \(entry.repoId, privacy: .public)")
        store.cancelDownload(entry)
    }

    func load(_ entry: ModelEntry) async {
        Self.logger.info("Begin load: \(entry.repoId, privacy: .public)")
        await store.load(entry)
        if store.isLoaded(entry) {
            Self.logger.info("Loaded: \(entry.repoId, privacy: .public)")
        } else if let err = store.lastError {
            Self.logger.error("Load failed: \(entry.repoId, privacy: .public) — \(err, privacy: .public)")
        }
    }

    func unload(_ entry: ModelEntry) {
        Self.logger.info("Unload: \(entry.repoId, privacy: .public)")
        store.unload(entry)
    }

    func requestDelete(_ entry: ModelEntry) {
        entryToDelete = entry
    }

    func confirmDelete() {
        guard let entry = entryToDelete else { return }
        Self.logger.info("Delete: \(entry.repoId, privacy: .public)")
        store.delete(entry)
        entryToDelete = nil
    }

    func toggleDefault(_ entry: ModelEntry) {
        if let idx = store.defaults.firstIndex(of: entry) {
            store.defaults.remove(at: idx)
            Self.logger.info("Removed from defaults: \(entry.repoId, privacy: .public)")
        } else {
            store.defaults.append(entry)
            Self.logger.info("Added to defaults: \(entry.repoId, privacy: .public)")
        }
        persistDefaults()
    }

    /// Kick off concurrent loads of every entry in `store.defaults`.
    /// Called once when the view first appears.
    func loadDefaults() async {
        guard !store.defaults.isEmpty else { return }
        Self.logger.info("Loading defaults: \(self.store.defaults.map(\.repoId).joined(separator: ", "), privacy: .public)")
        await store.loadDefaults()
        Self.logger.info("Defaults load pass complete")
    }

    // MARK: - UserDefaults persistence

    private func hydrateDefaultsFromUserDefaults() {
        let ids = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        let byId = Dictionary(uniqueKeysWithValues: Catalog.all.map { ($0.id, $0) })
        store.defaults = ids.compactMap { byId[$0] }
    }

    private func persistDefaults() {
        let ids = store.defaults.map(\.id)
        UserDefaults.standard.set(ids, forKey: Self.defaultsKey)
    }

    /// Background-tick watcher: logs once when a kicked-off download leaves
    /// the downloading state. The library doesn't expose a completion
    /// callback for `startDownload`, so we poll the @Observable state.
    private func watchDownloadCompletion(_ entry: ModelEntry) {
        Task { @MainActor [weak self] in
            while self?.store.isDownloading(entry) == true {
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard let self else { return }
            if self.store.isDownloaded(entry) {
                Self.logger.info("Finished download: \(entry.repoId, privacy: .public)")
            } else if let err = self.store.lastError {
                Self.logger.error("Download failed: \(entry.repoId, privacy: .public) — \(err, privacy: .public)")
            } else {
                Self.logger.info("Download cancelled: \(entry.repoId, privacy: .public)")
            }
        }
    }

    // MARK: - Formatting helpers

    static func formatGB(_ gb: Double) -> String {
        gb < 1 ? String(format: "%.0f MB", gb * 1000) : String(format: "%.1f GB", gb)
    }
}

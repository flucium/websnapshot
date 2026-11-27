import SwiftData

@MainActor
struct SnapshotHistoryViewState {
    let versions: [SnapshotHistoryService.Version]

    let selectedID: PersistentIdentifier

    var hasHistory: Bool {
        !versions.isEmpty
    }

    func isSelected(_ version: SnapshotHistoryService.Version) -> Bool {
        version.pdfFile.persistentModelID == selectedID
    }
}

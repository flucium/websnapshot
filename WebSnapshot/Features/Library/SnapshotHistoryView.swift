import SwiftUI
import SwiftData

struct SnapshotHistoryView: View {
    enum Placement {
        case popover
        case sidebar
    }

    private let snapshotHistoryViewState: SnapshotHistoryViewState

    private let placement: Placement

    private let open: (PDFFile) -> Void
    
    // <View: operation, layer>
    private let rowHeight: CGFloat = 50
    
    private let visibleVersionCount = 6
    // </View: operation, layer>
    
    init(_ snapshotHistoryViewState: SnapshotHistoryViewState, _ placement: Placement, open: @escaping (PDFFile) -> Void) {
        self.snapshotHistoryViewState = snapshotHistoryViewState

        self.placement = placement

        self.open = open
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Version History")
                .font(.headline)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(snapshotHistoryViewState.versions, id: \.pdfFile.persistentModelID) { version in
                            versionRow(version)
                        }
                    }
                }
                .frame(height: placement == .popover ? CGFloat(min(snapshotHistoryViewState.versions.count, visibleVersionCount)) * rowHeight : nil)
                .task(id: snapshotHistoryViewState.selectedID) {
                    if placement == .sidebar || snapshotHistoryViewState.versions.count > visibleVersionCount {
                        proxy.scrollTo(snapshotHistoryViewState.selectedID)
                    }
                }
            }
        }
        .frame(width: placement == .popover ? 280 : nil)
        .padding(12)
    }

    private func versionRow(_ version: SnapshotHistoryService.Version) -> some View {
        let isSelected = snapshotHistoryViewState.isSelected(version)

        return Button {
            open(version.pdfFile)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.secondary.opacity(version.isLatest ? 0 : 0.35))

                        Rectangle()
                            .fill(Color.secondary.opacity(version.number == 1 ? 0 : 0.35))
                    }
                    .frame(width: 1)

                    Circle()
                        .fill(version.isLatest ? Color.green : Color.secondary)
                        .frame(width: 9, height: 9)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    if let addedAt = version.pdfFile.addedAt {
                        Text(addedAt, format: .dateTime.year().month().day().hour().minute().second())
                            .font(.subheadline.weight(.semibold))
                    }

                    HStack(spacing: 5) {
                        Text("Version \(version.number)")

                        if version.isLatest {
                            Text("· Latest")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

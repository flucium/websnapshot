import SwiftData
import SwiftUI

struct LibraryTagEditorView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PDFTag.name) private var availableTags: [PDFTag]

    @ObservedObject var libraryViewState: LibraryViewState

    let pdfFile: PDFFile
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Tags")
                .font(.title2)

            Text(pdfFile.url.lastPathComponent)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack {
                TextField(
                    "New tag",
                    text: $libraryViewState.tagEditorNewTagName
                )
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addNewTag)

                Button("Add", action: addNewTag)
                    .disabled(
                        PDFTagService.normalizedName(
                            libraryViewState.tagEditorNewTagName
                        ).isEmpty
                    )
            }

            GroupBox("Selected Tags") {
                if libraryViewState.tagEditorTagNames.isEmpty {
                    Text("No tags selected.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        .padding(8)
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(libraryViewState.tagEditorTagNames, id: \.self) { tagName in
                                Button {
                                    removeTag(tagName)
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(tagName)
                                            .lineLimit(1)
                                        Image(systemName: "xmark")
                                            .font(.caption2)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .help("Remove \(tagName)")
                            }
                        }
                        .padding(8)
                    }
                    .frame(minHeight: 60, maxHeight: 120)
                }
            }

            if availableTags.isEmpty == false {
                GroupBox("Existing Tags") {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(availableTags) { tag in
                                Button {
                                    toggleTag(tag.name)
                                } label: {
                                    Label(
                                        tag.name,
                                        systemImage: containsTag(tag.name)
                                            ? "checkmark"
                                            : "tag"
                                    )
                                    .lineLimit(1)
                                }
                                .buttonStyle(.bordered)
                                .tint(
                                    containsTag(tag.name)
                                        ? .accentColor
                                        : nil
                                )
                            }
                        }
                        .padding(8)
                    }
                    .frame(minHeight: 80, maxHeight: 160)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()

                Button("Cancel") {
                    libraryViewState.closeTagEditor()
                }

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500)
        .frame(minHeight: 360)
        .alert(item: $libraryViewState.tagEditorAppError) { appError in
            AlertModal.show("Tags Could Not Be Saved", appError)
        }
    }

    private func addNewTag() {
        libraryViewState.tagEditorTagNames = PDFTagService.addingTag(
            libraryViewState.tagEditorNewTagName,
            to: libraryViewState.tagEditorTagNames
        )
        libraryViewState.tagEditorNewTagName = String()
    }

    private func toggleTag(_ name: String) {
        libraryViewState.tagEditorTagNames = PDFTagService.togglingTag(
            name,
            in: libraryViewState.tagEditorTagNames
        )
    }

    private func removeTag(_ name: String) {
        libraryViewState.tagEditorTagNames = PDFTagService.removingTag(
            name,
            from: libraryViewState.tagEditorTagNames
        )
    }

    private func containsTag(_ name: String) -> Bool {
        PDFTagService.containsTag(
            name,
            in: libraryViewState.tagEditorTagNames
        )
    }

    private func save() {
        do {
            try PDFTagService.replaceTags(
                libraryViewState.tagEditorTagNames,
                for: pdfFile,
                in: modelContext
            )
            libraryViewState.closeTagEditor()
        } catch {
            libraryViewState.tagEditorAppError = AppError.presentable(error)
        }
    }
}

struct PDFTagBadge: View {
    let name: String

    init(_ name: String) {
        self.name = name
    }

    var body: some View {
        Label(name, systemImage: "tag")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}

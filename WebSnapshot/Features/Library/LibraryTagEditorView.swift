import SwiftData
import SwiftUI

struct LibraryTagEditorView: View {
    @Environment(\.modelContext) private var modelContext

    @ObservedObject var libraryViewState: LibraryViewState

    let pdfFile: PDFFile
    
    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    newTagSection
                    selectedTagsSection
                }
                .padding(24)
            }

            Divider()

            footer
        }
        .frame(width: 560, height: 420)
        .background(.background)
        .alert(item: $libraryViewState.tagEditorAppError) { appError in
            AlertModal.show("Tags Could Not Be Saved", appError)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "tag.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Edit Tags")
                    .font(.title2.weight(.semibold))

                Text(pdfFile.url.lastPathComponent)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(pdfFile.url.lastPathComponent)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var newTagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Add a Tag", systemImage: "plus.circle")

            HStack(spacing: 10) {
                TextField(
                    "Enter a tag name",
                    text: $libraryViewState.tagEditorNewTagName
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit(addNewTag)

                Button(action: addNewTag) {
                    Label("Add", systemImage: "plus")
                }
                .disabled(isNewTagNameEmpty)
            }

            Text("Tag names are matched without regard to capitalization or spacing.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var selectedTagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Selected Tags", systemImage: "checkmark.circle")

                Spacer()

                Text("\(libraryViewState.tagEditorTagNames.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if libraryViewState.tagEditorTagNames.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tag.slash")
                        .font(.title2)
                        .foregroundStyle(.tertiary)

                    Text("No tags selected")
                        .font(.subheadline.weight(.medium))

                    Text("Add a tag above to organize this PDF.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 88)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(libraryViewState.tagEditorTagNames, id: \.self) { tagName in
                        SelectedTagButton(tagName) {
                            removeTag(tagName)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Label(
                "\(libraryViewState.tagEditorTagNames.count) tags",
                systemImage: "tag"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel") {
                libraryViewState.closeTagEditor()
            }
            .keyboardShortcut(.cancelAction)

            Button("Save", action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var isNewTagNameEmpty: Bool {
        PDFTagService.normalizedName(
            libraryViewState.tagEditorNewTagName
        ).isEmpty
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    private func addNewTag() {
        libraryViewState.tagEditorTagNames = PDFTagService.addingTag(
            libraryViewState.tagEditorNewTagName,
            to: libraryViewState.tagEditorTagNames
        )
        libraryViewState.tagEditorNewTagName = String()
    }

    private func removeTag(_ name: String) {
        libraryViewState.tagEditorTagNames = PDFTagService.removingTag(
            name,
            from: libraryViewState.tagEditorTagNames
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

private struct SelectedTagButton: View {
    let name: String
    let remove: () -> Void

    init(_ name: String, remove: @escaping () -> Void) {
        self.name = name
        self.remove = remove
    }

    var body: some View {
        Button(action: remove) {
            HStack(spacing: 6) {
                Image(systemName: "tag.fill")
                    .font(.caption)

                Text(name)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.35))
            }
        }
        .buttonStyle(.plain)
        .help("Remove \(name)")
        .accessibilityLabel("Remove \(name)")
    }
}

import SwiftData
import SwiftUI

struct LibraryTagEditorView: View {
    @Environment(\.modelContext) private var modelContext

    @ObservedObject var libraryTagEditorViewState: LibraryTagEditorViewState

    let pdfFile: PDFFile
    
    let close: () -> Void

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
        .alert(item: $libraryTagEditorViewState.appError) {
            appError in
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

                Text(pdfFile.resolvedURL.lastPathComponent)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(pdfFile.resolvedURL.lastPathComponent)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var newTagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Add a Tag",  "plus.circle")

            HStack(spacing: 10) {
                TextField("Enter a tag name", text: $libraryTagEditorViewState.newTagName)
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
                sectionTitle("Selected Tags",  "checkmark.circle")

                Spacer()

                Text("\(libraryTagEditorViewState.tagNames.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if libraryTagEditorViewState.tagNames.isEmpty {
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(libraryTagEditorViewState.tagNames, id: \.self) {
                        tagName in
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
            Label("\(libraryTagEditorViewState.tagNames.count) tags",systemImage: "tag")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel") {
                close()
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
        PDFTagService.normalizedName(libraryTagEditorViewState.newTagName).isEmpty
    }

    private func sectionTitle(_ title: String, _ systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    private func addNewTag() {
        LibraryTagEditorViewService.addNewTag(libraryTagEditorViewState)
    }

    private func removeTag(_ name: String) {
        LibraryTagEditorViewService.removeTag(libraryTagEditorViewState, name)
    }

    private func save() {
        if LibraryTagEditorViewService.save(libraryTagEditorViewState, pdfFile, modelContext) {
            close()
        }
    }
}

private struct SelectedTagButton: View {
    let name: String
    let remove: () -> Void

    init(_ name: String, _ remove: @escaping () -> Void) {
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

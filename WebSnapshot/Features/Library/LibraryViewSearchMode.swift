enum SearchMode: CaseIterable, Hashable {
    case all
    case title
    case tag

    var title: String {
        switch self {
        case .all:
            "All"
        case .title:
            "Title"
        case .tag:
            "Tag"
        }
    }
}

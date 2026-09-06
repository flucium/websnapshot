import Foundation
import Darwin

final class FileIO{
    enum Availability: Equatable {
        case available
        case missing
        case unavailable
    }

    static func availability(_ url: URL) -> Availability {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if isInTrash(url) {
            return .missing
        }

        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return .available
        } catch {
            guard isMissingFileError(error) else {
                return .unavailable
            }

            guard let names = try? FileManager.default.contentsOfDirectory(
                atPath: url.deletingLastPathComponent().path
            ), names.contains(url.lastPathComponent) == false else {
                return .unavailable
            }
            return .missing
        }
    }

    static func isMissingFileError(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSCocoaErrorDomain
            && (error.code == CocoaError.fileReadNoSuchFile.rawValue
                || error.code == CocoaError.fileNoSuchFile.rawValue))
            || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT))
    }

    private static func isInTrash(_ url: URL) -> Bool {
        var relationship = FileManager.URLRelationship.other
        do {
            try FileManager.default.getRelationship(
                &relationship, of: .trashDirectory, in: [], toItemAt: url
            )
            return relationship == .contains || relationship == .same
        } catch {
            return false
        }
    }

    static func exists(
        _ url:URL
    ) -> Bool{
        let isAccessing = url.startAccessingSecurityScopedResource()
        
        defer {
            if isAccessing {
                url
                    .stopAccessingSecurityScopedResource()
            }
        }
        
        return FileManager.default
            .fileExists(
                atPath: url.path
            )
    }
    
    static func delete(
        _ url: URL
    ) throws{
        let isAccessing = url.startAccessingSecurityScopedResource()
        
        defer {
            if isAccessing {
                url
                    .stopAccessingSecurityScopedResource()
            }
        }
        
        do{
            try FileManager.default
                .removeItem(
                    at: url
                )
        } catch {
            throw AppError(
                error
            )
        }
    }
}

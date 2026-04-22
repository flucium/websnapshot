import Foundation
import SwiftData

final class DirectoryService {
    
    @discardableResult
    static func save(_ url: URL, _ modelContext: ModelContext) throws -> Directory {
        
        let bookmarkData = URL.securityScopedBookmarkData(url)

        do {
                    
            if let directory = try fetch(modelContext).first(
                where: { $0.url == url
                }){
                        
                if let bookmarkData {
                    directory.bookmarkData = bookmarkData
                }
                
                try modelContext.save()
                            
                return directory
            }else{
                let directory = Directory( url,  bookmarkData)

                modelContext.insert(directory)
                        
                try modelContext.save()
                        
                return directory
            }

      
        } catch {
            throw AppError( error)
        }
    }
    
    
    static func delete(_ url: URL, _ modelContext: ModelContext) throws {
        
        do {
            
            let matched = try fetch(modelContext).filter {
                $0.url == url
            }

            for entry in matched {
                modelContext.delete(entry)
            }

            if matched.isEmpty == false{
                try modelContext.save()
            }
            
        } catch {
            throw AppError( error)
        }
    }

    static func refreshBookmarks(in directoryURLs: [URL], _ modelContext: ModelContext) throws {
        
        let directoryPaths = Set( directoryURLs.map{
            $0.standardizedFileURL.path
        })

        guard Set(directoryURLs.map{
            $0.standardizedFileURL.path
        }).isEmpty == false else {
            return
        }

        var needs = false
        
        do {
            for directory in try fetch(modelContext) {
                let fileURL = directory.resolvedURL
              
                guard directoryPaths.contains(fileURL.deletingLastPathComponent().standardizedFileURL.path),
                    
                    let bookmarkData = URL.securityScopedBookmarkData(fileURL)
                        
                else {
                    continue
                }

                directory.bookmarkData = bookmarkData
                
                needs = true
            }

            if needs {
                try modelContext.save()
            }
        } catch {
            throw AppError(error)
        }
    }

    
    private static func fetch(_ modelContext:ModelContext) throws -> [Directory] {
        return try modelContext.fetch(FetchDescriptor<Directory>())
    }
}

final class DirectoryHistoryService {
    private static let maxDirectoryHistoryCount = 10
    
    @discardableResult
    static func save(_ url:URL, _ modelContext:ModelContext) throws -> DirectoryHistory{
        let bookmarkData = URL.securityScopedBookmarkData(url)

        do {
            let directories = try fetch(modelContext)

            if directories.contains(where:{
                $0.url == url
            }) {
                throw AppError.display(message: "Directory history already exists.")
            }

            guard directories.count < maxDirectoryHistoryCount else {
                throw AppError.display(message: "Directory history limit reached.")
            }

            let directory = DirectoryHistory(url, bookmarkData, usedAt: Date())

            modelContext.insert(directory)

            try modelContext.save()

            return directory
        } catch {
            throw AppError(error)
        }
    }
    
//    static func delete(_ url:URL, _ modelContext:ModelContext) throws {
//        do {
//            let matched = try fetch(modelContext).filter{
//                $0.url == url
//            }
//
//            for entry in matched {
//                modelContext.delete(entry)
//            }
//
//            if matched.isEmpty == false{
//                try modelContext.save()
//            }
//            
//        } catch {
//            throw AppError(error)
//        }
//    }
    
    static func set(_ url:URL, _ modelContext:ModelContext) throws -> DirectoryHistory{
       
        let bookmarkData = URL.securityScopedBookmarkData(url)

        do {
            let histories = try fetch(modelContext)

            if histories.contains(where:{
                $0.url == url
            }) {
                throw AppError.display(message: "Directory history already exists.")
            }

            guard histories.count < maxDirectoryHistoryCount else {
                throw AppError.display(message: "Directory history limit reached.")
            }

            let history = DirectoryHistory(url, bookmarkData, usedAt: Date())

            modelContext.insert(history)

            try modelContext.save()

            return history
        } catch {
            throw AppError(error)
        }
    }
    
    static func unset(_ url:URL, _ modelContext:ModelContext) throws {
        do {
            let matched = try fetch(modelContext).filter{
                $0.url == url
            }

            let directoryURLs = matched.map{
                $0.resolvedURL.standardizedFileURL
            }

            defer {
                for directoryURL in (directoryURLs.filter{
                    $0.startAccessingSecurityScopedResource()}){
                    directoryURL.stopAccessingSecurityScopedResource()
                }
            }

            try DirectoryService.refreshBookmarks(in: directoryURLs,modelContext)

            for entry in matched {
                modelContext.delete(entry)
            }

            if matched.isEmpty == false{
                try modelContext.save()
            }
        } catch {
            throw AppError(error)
        }
    }
    
    static func exists(_ url: URL,_ modelContext:ModelContext) -> Bool{
        return (try? fetch(modelContext).contains {
            $0.url == url
        }) ?? false
    }
    
    private static func fetch(_ modelContext:ModelContext) throws -> [DirectoryHistory] {
        return try modelContext.fetch(FetchDescriptor<DirectoryHistory>(sortBy: [SortDescriptor(\.usedAt, order: .reverse)]))
    }
}

import Foundation

final class FileIO{
    static func exists(_ url:URL) -> Bool{
        FileManager.default.fileExists(atPath: url.path())
    }
    
    static func delete(_ url: URL) throws{
        do{
            try FileManager.default.removeItem(at: url)
        }catch{
            throw AppError.invalidIO("Invalid file deletion.")
        }
    }
}

import Foundation

class FileIO {
    static func getFiles(_ url: URL)throws -> [URL]{
        
        if let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory {
            if isDir == false{
                throw AppError(AppError.invalidFileType)
            }
        }
        
        do{
            return try FileManager.default.contentsOfDirectory(at: url,includingPropertiesForKeys: nil)
        }catch{
            throw AppError(error)
        }
    }
    
    static func isDir(_ url: URL) throws -> Bool{
        if let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory{
            return isDir
        }else{
            throw AppError(AppError.invalidFileType)
        }
    }
    
    static func isFile(_ url:URL) throws -> Bool {
        if let isFile = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile{
            return isFile
        }else{
            throw AppError(AppError.invalidFileType)
        }
    }
    
    static func isPDFFile(_ url:URL,) throws -> Bool{
//        do{
//            if try isFile(url){
//                return url.pathExtension.lowercased() == "pdf"
//            }else{
//                throw AppError(AppError.invalidFileType)
//            }
//        }catch{
//            throw AppError(error)
//        }
        
        if ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) != nil){
            return url.pathExtension.lowercased() == "pdf"
        }else{
            throw AppError(AppError.invalidFileType)
        }
    }
}

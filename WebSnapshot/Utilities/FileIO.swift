//
//  FileIO.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//


import Foundation
import CoreGraphics

func getFiles(url:URL) -> [URL] {
    do {
        let items = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        return items.filter { $0.path.hasPrefix(url.path) }
    } catch {
        return []
    }
}

func delete(url: URL) -> Bool{
    do{
        try FileManager.default.removeItem(atPath: url.path)
        
        return true
    }catch{
        return false
    }
}

func exists(url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}

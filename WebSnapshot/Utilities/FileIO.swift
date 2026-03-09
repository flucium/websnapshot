//
//  FileIO.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/08.
//

import Foundation
import CoreGraphics



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

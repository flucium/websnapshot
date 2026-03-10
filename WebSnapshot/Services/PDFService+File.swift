//
//  Untitled.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//


import Foundation
import CoreGraphics

func deletePDFFile(url:URL) throws {
    
    guard exists(url: url) else{
        throw CocoaError(.fileNoSuchFile)
    }
    
    guard isPDFFile(url: url) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    
    guard delete(url: url) else {
        throw CocoaError(.fileWriteNoPermission)
    }
    
}


func isPDFFile(url: URL) -> Bool {
  
    do {
        
        guard let fileSize = ((try FileManager.default.attributesOfItem(atPath: url.path))[.size] as? NSNumber)?.uint64Value, fileSize >= 8 else {
            return false
        }
        
        let fileHandle = try FileHandle(forReadingFrom: url)
        
        defer {
            try? fileHandle.close()
        }
        
        
        let fileHeader = try fileHandle.read(upToCount: 8) ?? Data()
        guard fileHeader.count >= 8 else {
            return false
        }
        
        guard fileHeader.starts(with: Data("%PDF-".utf8)) else {
            return false
        }
        
        
        guard let version = String(data: fileHeader.subdata(in: 5..<8), encoding: .ascii),
              version.range(of: #"^1\.[0-7]$"#, options: .regularExpression) != nil else {
            
            return false
        }
        
        
        try fileHandle.seek(toOffset: fileSize - UInt64(Int(min(fileSize, 4096))))
        
        
        let end = try fileHandle.readToEnd() ?? Data()
        
        guard end.range(of: Data("startxref".utf8), options: .backwards) != nil else {
            return false
            
        }
    
        guard end.range(of: Data("%%EOF".utf8), options: .backwards) != nil else {
            return false
        }
        
    } catch {
        return false
    }

    guard let doc = CGPDFDocument(url as CFURL) else {
        return false
    }
    
    return doc.numberOfPages > 0
    
}

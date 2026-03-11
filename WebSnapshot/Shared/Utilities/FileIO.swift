//
//  FileIO.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//


import Foundation
import CoreGraphics

class FileIO {

    func delete(url: URL) -> Result<Void, Error> {
        do {
            try FileManager.default.removeItem(atPath: url.path)
            return .success(())
        } catch {
            return .failure(error)
        }
    }


    func exists(url: URL) -> Result<Bool,Error> {
        return .success(FileManager.default.fileExists(atPath: url.path))
    }


}

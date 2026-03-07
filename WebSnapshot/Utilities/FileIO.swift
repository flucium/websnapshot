//
//  FileIO.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/08.
//

import Foundation

func deletePDFFile(path: String) {
    do {
        try FileManager.default.removeItem(atPath: path)
    } catch {
        //
    }
}

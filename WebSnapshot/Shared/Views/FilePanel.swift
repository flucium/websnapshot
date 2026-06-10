import Foundation
import AppKit
import WebKit
import UniformTypeIdentifiers

@MainActor
func savePanel(_ title:String,_ url:URL?,_ pdfFileDocument:PDFFileDocument?) throws -> URL?{
    guard let data = pdfFileDocument?.data else{
        return nil
    }
    
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.pdf]
    panel.canCreateDirectories = true
    panel.title = "Save"
    panel.nameFieldStringValue = URL.pdfFileName(title,url)
    
    
    guard panel.runModal() == .OK, let destination = panel.url else {
        return nil
    }
    
    do{
        try data.write(to: destination,options: .atomic)
        
        return destination
    }catch{
        throw AppError.invalidIO("Write data to \(destination.path) failed.")
    }

}

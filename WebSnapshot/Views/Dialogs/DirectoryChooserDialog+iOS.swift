//
//  DirectoryChooserDialog+iOS.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//

#if os(iOS)

import UIKit
import UniformTypeIdentifiers

extension DirectoryChooserDialog {

    static func choose(
        from viewController: UIViewController,
        completion: @escaping (URL?) -> Void
    ) {
        let picker = UIDocumentPickerViewController(
       
            forOpeningContentTypes: [.folder],
            
            asCopy: false
        )

        picker.allowsMultipleSelection = false
        
        viewController.present(picker, animated: true)
    }
}

#endif

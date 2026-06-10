import SwiftUI

final class AlertModal{
    static func show(_ title:String,_ message:String) -> Alert{
        
        Alert(
            title: Text("\(title)"),
            message: Text("\(message)"),
            dismissButton: .default(Text("OK"))
        )
    }
}

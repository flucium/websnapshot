import Foundation
import WebKit

final class FetchViewService{
    static func fetch(_ url:URL) throws -> WebPage{
        
        let url = if url.isSupportedWebURL == false{
            url.noSchemeToScheme
        }else{
            url
        }
        
        do{
            let webPage = try WebService.fetch(url!)
            
            if webPage.url == nil || webPage.url!.isSupportedWebURL == false{
                throw AppError.invalidURL("Invalid URL.")
            }
            
            return webPage
        }catch{
            throw AppError.invalidLoad("Fetch web page failed.")
        }
    }
}

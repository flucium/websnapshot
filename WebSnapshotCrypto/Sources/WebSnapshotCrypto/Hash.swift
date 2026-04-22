import Foundation
import CryptoKit
import CommonCrypto



@available(macOS 10.15, *)
public final class SHA2{
    
    public enum Algorithm{
        case sha256
        case sha512
    }
    
    public static func digest(_ algorithm:Algorithm, _ data:Data, _ stretch:Int = 0) -> Data{
        switch algorithm{
        case .sha256:
            return sha256(data,stretch)
        case .sha512:
            return sha512(data,stretch)
        }
    }
    
    private static func sha256(_ data:Data,_ stretch:Int = 0) -> Data{
        var hasher = SHA256()
        
        hasher.update(data: data)
        
        for _ in 0 ..< stretch{
            hasher.update(data: data)
        }
        
        let digest = hasher.finalize()
        
        let result = Data(digest)
        
        return result
    }
    
    private static func sha512(_ data:Data, _ stretch:Int = 0) -> Data{
        var hasher = SHA512()
        
        hasher.update(data: data)
        
        for _ in 0 ..< stretch{
            hasher.update(data: data)
        }
        
        let digest = hasher.finalize()
        
        let result = Data(digest)
        
        return result
    }
    
    
}

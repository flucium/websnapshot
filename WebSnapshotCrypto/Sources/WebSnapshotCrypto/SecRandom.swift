import Foundation
import CryptoKit
import Security

public enum SecRandomError: Error{
    case invalidLength
    case failed(OSStatus)
}

@available(macOS 10.15, *)
public func generateSymmetricKey() -> Data{
    let symmetricKey:SymmetricKey = SymmetricKey(size:.bits256)
    
    let data:Data = symmetricKey.withUnsafeBytes{Data($0)}

    return data
}

public func generateNonce(_ len:Int = 96) throws -> Data{
    return try generateSecRandomData(len)
}

public func generateSecRandomData(_ len:Int = 16) throws -> Data{
    
    guard len > 0 else{
        throw SecRandomError.invalidLength
    }
    
    
    var data:Data = Data(count:len)
    
    let err = data.withUnsafeMutableBytes{
        SecRandomCopyBytes(kSecRandomDefault, len,$0.baseAddress!)
    }
    
    guard err == errSecSuccess else{
        throw SecRandomError.failed(err)
    }
    
    return data
}

import Foundation
import CryptoKit

public enum AESError:Error{
    case invalidKeyLength
    case invalidNonceLength
}

public enum AESMode{
    case gcm
    case keyWrap
}

@available(macOS 10.15, *)
public final class AES {
    
    let keyLength:SymmetricKeySize = SymmetricKeySize.bits256
    
    let nonceLength:Int = 12
    
    var key:Data
    
    var nonce:Data? = nil
    
    var mode:AESMode
    
    init(_ key: Data, _ nonce:Data? = nil, _ mode:AESMode) {
        self.key = key
        self.nonce = nonce
        self.mode = mode
    }
    
    public func encrypt(_ plain:Data) throws -> Data{
        
        if self.key.isEmpty || byteToBit(self.key.count) != self.keyLength.bitCount{
            throw AESError.invalidKeyLength
        }
        
        if self.nonce == nil || self.nonce!.count != self.nonceLength{
            throw AESError.invalidNonceLength
        }
        
        switch self.mode {
            case .gcm:
            return try aes_gcm_seal(plain)
            
        case .keyWrap:
            preconditionFailure()
        }
        
    }
    
    public func decrypt(_ cipher:Data) throws -> Data{
        
        if self.key.isEmpty || byteToBit(self.key.count) != self.keyLength.bitCount{
            throw AESError.invalidKeyLength
        }
        
        
        switch self.mode {
            case .gcm:
            return try aes_gcm_open(cipher)
            
        case .keyWrap:
            preconditionFailure()
        }
        
    }
    
    private func aes_gcm_seal(_ plain:Data) throws -> Data{
        
        let key:SymmetricKey = CryptoKit.SymmetricKey(data: self.key)
        
        let nonce:CryptoKit.AES.GCM.Nonce = try CryptoKit.AES.GCM.Nonce(data: self.nonce!)
        
        let sealBox:CryptoKit.AES.GCM.SealedBox = try CryptoKit.AES.GCM.seal(plain, using: key, nonce: nonce)
        
        return sealBox.combined!
    }
    
    private func aes_gcm_open(_ cipher:Data) throws -> Data{
        
        let key:SymmetricKey = CryptoKit.SymmetricKey(data: self.key)
        
        let sealBox:CryptoKit.AES.GCM.SealedBox = try CryptoKit.AES.GCM.SealedBox(combined: cipher)
        
        let plain:Data = try CryptoKit.AES.GCM.open(sealBox, using: key)
        
        return plain
    }
    
    private func aes_key_wrap(_ key:Data) throws -> Data{
        preconditionFailure()
    }
    
    private func aes_key_unwrap(_ key:Data) throws -> Data{
        preconditionFailure()
    }
}

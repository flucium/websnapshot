import Testing
import Foundation
@testable import WebSnapshotCrypto

struct SHA2Tests{
    @Test func testSHA256(){
        #expect(SHA2.digest(SHA2.Algorithm.sha256,Data("Hello".utf8)).hex == "185f8db32271fe25f561a6fc938b2e264306ec304eda518007d1764826381969")
        
        #expect(SHA2.digest(SHA2.Algorithm.sha256, Data("Hello".utf8)).hex.uppercased() == "185F8DB32271FE25F561A6FC938B2E264306EC304EDA518007D1764826381969")
    }
    
    @Test func testSHA512(){
        
        #expect(SHA2.digest(SHA2.Algorithm.sha512,Data("Hello".utf8)).hex == "3615f80c9d293ed7402687f94b22d58e529b8cc7916f8fac7fddf7fbd5af4cf777d3d795a7a00a16bf7e7f3fb9561ee9baae480da9fe7a18769e71886b03f315")
        
        
        #expect(SHA2.digest(SHA2.Algorithm.sha512,Data("Hello".utf8)).hex.uppercased() == "3615F80C9D293ED7402687F94B22D58E529B8CC7916F8FAC7FDDF7FBD5AF4CF777D3D795A7A00A16BF7E7F3FB9561EE9BAAE480DA9FE7A18769E71886B03F315")
        
    }
}

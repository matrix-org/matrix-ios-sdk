//
//  MXEventDecryptionResult+DecryptEvent.swift
//  MatrixSDK
//
//  Created by Element on 28/06/2022.
//

import Foundation

#if DEBUG && os(iOS)

import MatrixSDKCrypto

extension MXEventDecryptionResult {
    enum Error: Swift.Error {
        case invalidEvent
    }
    
    /// Convert Rust-based `DecryptedEvent` into legacy SDK `MXEventDecryptionResult`
    convenience init(event: DecryptedEvent) throws {
        self.init()
        
        guard let clear = MXTools.deserialiseJSONString(event.clearEvent) as? [AnyHashable: Any] else {
            throw Error.invalidEvent
        }
        
        clearEvent = clear
        senderCurve25519Key = event.senderCurve25519Key
        claimedEd25519Key = event.claimedEd25519Key
        forwardingCurve25519KeyChain = event.forwardingCurve25519Chain
    }
}

#endif

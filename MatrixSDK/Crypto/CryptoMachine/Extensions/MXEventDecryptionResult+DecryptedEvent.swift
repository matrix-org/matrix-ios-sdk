//
// Copyright 2022 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation

#if DEBUG

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
        
        // `Untrusted` state from rust is currently ignored as it lacks "undecided" option,
        // will be changed in a future PR into:
        // isUntrusted = event.verificationState == VerificationState.untrusted
        isUntrusted = false
    }
}

#endif

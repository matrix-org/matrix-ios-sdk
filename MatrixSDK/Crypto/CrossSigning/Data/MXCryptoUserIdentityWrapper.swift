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
import MatrixSDKCrypto

/// Convenience wrapper around `MatrixSDKCrypto`'s `UserIdentity`
/// which can be used to create `MatrixSDK`s `MXCrossSigningInfo`
///
/// Note: The class is marked as final with internal initializer,
/// meaning it cannot be created or subclassed from outside the SDK.
@objcMembers public final class MXCryptoUserIdentityWrapper: NSObject {
    public let userId: String
    public let masterKeys: MXCrossSigningKey?
    public let selfSignedKeys: MXCrossSigningKey?
    public let userSignedKeys: MXCrossSigningKey?
    public let trustLevel: MXUserTrustLevel
    
    internal init(identity: UserIdentity, isVerified: Bool) {
        switch identity {
        case .own(let userId, _, let masterKey, let userSigningKey, let selfSigningKey):
            self.userId = userId
            // Note: `trustsOurOwnDevice` is not currently used, instead using second `isVerified` parameter
            self.masterKeys = .init(jsonString: masterKey)
            self.selfSignedKeys = .init(jsonString: selfSigningKey)
            self.userSignedKeys = .init(jsonString: userSigningKey)
        case .other(let userId, let masterKey, let selfSigningKey):
            self.userId = userId
            self.masterKeys = .init(jsonString: masterKey)
            self.selfSignedKeys = .init(jsonString: selfSigningKey)
            self.userSignedKeys = nil
        }
        
        // `MatrixSDKCrypto` does not distinguish local and cross-signed
        // verification status for users
        trustLevel = MXUserTrustLevel(
            crossSigningVerified: isVerified,
            locallyVerified: isVerified
        )
    }
}

private extension MXCrossSigningKey {
    convenience init?(jsonString: String) {
        guard let json =  MXTools.deserialiseJSONString(jsonString) as? [AnyHashable: Any] else {
            return nil
        }
        self.init(fromJSON: json)
    }
}

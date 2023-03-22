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

/// Convenience struct which transforms `MatrixSDKCrypto` cross signing info formats
/// into `MatrixSDK` `MXCrossSigningInfo` formats.
struct MXCrossSigningInfoSource {
    private let source: MXCryptoUserIdentitySource
    
    init(source: MXCryptoUserIdentitySource) {
        self.source = source
    }
    
    func crossSigningInfo(userId: String) -> MXCrossSigningInfo? {
        guard let identity = source.userIdentity(userId: userId) else {
            return nil
        }
        let isVerified = source.isUserVerified(userId: userId)
        return .init(
            userIdentity: .init(
                identity: identity,
                isVerified: isVerified
            )
        )
    }
}

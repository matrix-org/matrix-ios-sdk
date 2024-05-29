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

extension Device {
    static func stub(
        userId: String = "Alice",
        deviceId: String = "Device1",
        displayName: String = "Alice's iPhone",
        isBlocked: Bool = false,
        locallyTrusted: Bool = true,
        crossSigningTrusted: Bool = true
    ) -> Device {
        return .init(
            userId: userId,
            deviceId: deviceId,
            keys: [
                "ed25519:Device1": "ABC",
                "curve25519:Device1": "XYZ",
            ],
            algorithms: [
                "ed25519",
                "curve25519"
            ],
            displayName: displayName,
            isBlocked: isBlocked,
            locallyTrusted: locallyTrusted,
            crossSigningTrusted: crossSigningTrusted,
            firstTimeSeenTs: 0,
            dehydrated: false
        )
    }
}

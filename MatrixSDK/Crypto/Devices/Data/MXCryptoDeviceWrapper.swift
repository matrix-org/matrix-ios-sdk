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

/// Convenience wrapper around `MatrixSDKCrypto`'s `Device`
/// which can be used to create `MatrixSDK`s `MXDeviceInfo`
///
/// Note: The class is marked as final with internal initializer,
/// meaning it cannot be created or subclassed from outside the SDK.
@objcMembers public final class MXCryptoDeviceWrapper: NSObject {
    public let userId: String
    public let deviceId: String
    public let algorithms: [String]
    public let keys: [String: String]
    public let unsignedData: [String: Any]
    public let trustLevel: MXDeviceTrustLevel
    
    internal init(device: Device) {
        userId = device.userId
        deviceId = device.deviceId
        algorithms = device.algorithms
        keys = device.keys
        if let displayName = device.displayName {
            unsignedData = [
                "device_display_name": displayName
            ]
        } else {
            unsignedData = [:]
        }
        
        let status: MXDeviceVerification
        if device.isBlocked {
            status = .blocked
        } else if device.locallyTrusted {
            status = .verified
        } else {
            // Note: currently not distinguishing between unknown and unverified
            status = .unknown
        }
        
        trustLevel = MXDeviceTrustLevel(
            localVerificationStatus: status,
            crossSigningVerified: device.crossSigningTrusted
        )
    }
}

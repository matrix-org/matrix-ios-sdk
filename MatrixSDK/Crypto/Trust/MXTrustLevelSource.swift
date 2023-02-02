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

/// Convenience struct which transforms `MatrixSDKCrypto` trust levels
/// into `MatrixSDK` `MXUserTrustLevel`, `MXDeviceTrustLevel` and `MXUsersTrustLevelSummary` formats.
struct MXTrustLevelSource {
    private let userIdentitySource: MXCryptoUserIdentitySource
    private let devicesSource: MXCryptoDevicesSource
    
    init(userIdentitySource: MXCryptoUserIdentitySource, devicesSource: MXCryptoDevicesSource) {
        self.userIdentitySource = userIdentitySource
        self.devicesSource = devicesSource
    }
    
    func userTrustLevel(userId: String) -> MXUserTrustLevel {
        let isVerified = userIdentitySource.isUserVerified(userId: userId)
        
        // `MatrixSDKCrypto` does not distinguish local and cross-signed
        // verification status for users
        return .init(
            crossSigningVerified: isVerified,
            locallyVerified: isVerified
        )
    }
    
    func deviceTrustLevel(userId: String, deviceId: String) -> MXDeviceTrustLevel? {
        guard let device = devicesSource.device(userId: userId, deviceId: deviceId) else {
            return nil
        }
        return .init(
            localVerificationStatus: device.locallyTrusted ? .verified : .unverified,
            crossSigningVerified: device.crossSigningTrusted
        )
    }
    
    func trustLevelSummary(userIds: [String]) -> MXUsersTrustLevelSummary {
        return .init(
            trustedUsersProgress: trustedUsers(userIds: userIds),
            andTrustedDevicesProgress: trustedDevices(userIds: userIds)
        )
    }
    
    private func trustedUsers(userIds: [String]) -> Progress {
        let verifiedUsers = userIds.filter {
            userIdentitySource.isUserVerified(userId: $0)
        }
        
        let progress = Progress(totalUnitCount: Int64(userIds.count))
        progress.completedUnitCount = Int64(verifiedUsers.count)
        return progress
    }
    
    private func trustedDevices(userIds: [String]) -> Progress {
        let devices = userIds.flatMap {
            devicesSource.devices(userId: $0)
        }
        let trustedDevices = devices.filter {
            $0.crossSigningTrusted || $0.locallyTrusted
        }

        let progress = Progress(totalUnitCount: Int64(devices.count))
        progress.completedUnitCount = Int64(trustedDevices.count)
        return progress
    }
}

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
@testable import MatrixSDK

#if DEBUG && os(iOS)

import MatrixSDKCrypto

class DevicesSourceStub: MXCryptoDevicesSource {
    var deviceCurve25519Key: String? {
        return nil
    }
    
    var deviceEd25519Key: String? {
        return nil
    }
    
    var devices = [String: [String: Device]]()
    
    func device(userId: String, deviceId: String) -> Device? {
        return devices[userId]?[deviceId]
    }
    
    func devices(userId: String) -> [Device] {
        return devices[userId]?.map { $0.value } ?? []
    }
}

class UserIdentitySourceStub: MXCryptoUserIdentitySource {
    var identities = [String: UserIdentity]()
    func userIdentity(userId: String) -> UserIdentity? {
        return identities[userId]
    }
    
    var verification = [String: Bool]()
    func isUserVerified(userId: String) -> Bool {
        return verification[userId] ?? false
    }
}

#endif

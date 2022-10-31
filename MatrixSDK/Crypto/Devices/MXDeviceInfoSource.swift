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

/// Convenience struct which transforms `MatrixSDKCrypto` device formats
/// into `MatrixSDK` `MXDeviceInfo` formats.
struct MXDeviceInfoSource {
    private let source: MXCryptoDevicesSource
    
    init(source: MXCryptoDevicesSource) {
        self.source = source
    }
    
    func deviceInfo(userId: String, deviceId: String) -> MXDeviceInfo? {
        guard let device = source.device(userId: userId, deviceId: deviceId) else {
            return nil
        }
        return .init(device: .init(device: device))
    }
    
    func devicesInfo(userId: String) -> [String: MXDeviceInfo] {
        return source
            .devices(userId: userId)
            .reduce(into: [String: MXDeviceInfo]()) { dict, device in
                dict[device.deviceId] = .init(device: .init(device: device))
            }
    }
    
    func devicesMap(userIds: [String]) -> MXUsersDevicesMap<MXDeviceInfo> {
        let map = MXUsersDevicesMap<MXDeviceInfo>()
        for userId in userIds {
            map.setObjects(devicesInfo(userId: userId), forUser: userId)
        }
        return map
    }
}

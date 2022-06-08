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
import Realm

class MXRealmBeaconInfoSummary: RLMObject {
    
    // MARK: - Properties

    @objc dynamic var identifier: String = ""
    @objc dynamic var userId: String = ""
    @objc dynamic var roomId: String = ""
    @objc dynamic var deviceId: String?
    @objc dynamic var beaconInfo: MXRealmBeaconInfo?
    @objc dynamic var lastBeacon: MXRealmBeacon?
    
    // MARK: - Setup
    
    convenience init(identifier: String,
                  userId: String,
                  roomId: String,
                  deviceId: String? = nil,
                  beaconInfo: MXRealmBeaconInfo,
                  lastBeacon: MXRealmBeacon? = nil) {
        
        // https://www.mongodb.com/docs/realm-legacy/docs/swift/latest/#adding-custom-initializers-to-object-subclasses
        self.init() // Please note this says 'self' and not 'super'
        
        self.identifier = identifier
        self.userId = userId
        self.roomId = roomId
        self.deviceId = deviceId
        self.beaconInfo = beaconInfo
        self.lastBeacon = lastBeacon
    }
    
    override class func primaryKey() -> String? {
        return "identifier"
    }
}

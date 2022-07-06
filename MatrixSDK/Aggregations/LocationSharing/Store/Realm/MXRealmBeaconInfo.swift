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

class MXRealmBeaconInfo: RLMObject {
    
    // MARK: - Properties
    
    /// Beacon user id
    @objc dynamic var userId: String?

    /// Beacon room id
    @objc dynamic var roomId: String?

    /// Beacon description
    @objc dynamic var desc: String?
    
    /// How long from the last event until we consider the beacon inactive in milliseconds
    @objc dynamic var timeout: Int = 0

    /// Mark the start of an user's intent to share ephemeral location information.
    /// When the user decides they would like to stop sharing their live location the original m.beacon_info's live property should be set to false.
    @objc dynamic var isLive: Bool = false

    /// the type of asset being tracked as per MSC3488
    @objc dynamic var assetTypeRawValue: Int = 0
    
    var assetType: MXEventAssetType {
        return MXEventAssetType(rawValue: UInt(self.assetTypeRawValue)) ?? MXEventAssetType.user
    }

    /// Creation timestamp of the beacon on the client
    /// Milliseconds since UNIX epoch
    @objc dynamic var timestamp: Int = 0
    
    /// The event id of the event used to build the MXBeaconInfo.
    @objc dynamic var originalEventId: String?
    
    // MARK: - Setup
    
    convenience init(userId: String? = nil,
                  roomId: String? = nil,
                  desc: String? = nil,
                  timeout: Int,
                  isLive: Bool,
                  assetTypeRawValue: Int,
                  timestamp: Int,
                  originalEventId: String? = nil) {
        
        // https://www.mongodb.com/docs/realm-legacy/docs/swift/latest/#adding-custom-initializers-to-object-subclasses
        self.init() //Please note this says 'self' and not 'super'
        
        self.userId = userId
        self.roomId = roomId
        self.desc = desc
        self.timeout = timeout
        self.isLive = isLive
        self.assetTypeRawValue = assetTypeRawValue
        self.timestamp = timestamp
        self.originalEventId = originalEventId
    }
}

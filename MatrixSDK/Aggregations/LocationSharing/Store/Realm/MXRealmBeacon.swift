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

class MXRealmBeacon: RLMObject {
    
    // MARK: - Properties
    
    /// Coordinate latitude
    @objc dynamic var latitude: Double = 0

    /// Coordinate longitude
    @objc dynamic var longitude: Double = 0

    /// URI string (i.e. "geo:51.5008,0.1247;u=35")
    @objc dynamic var geoURI: String = ""
    
    /// Location description
    @objc dynamic var desc: String?
    
    /// The event id of the associated beaco info
    @objc dynamic var beaconInfoEventId: String = ""

    /// Creation timestamp of the beacon on the client
    /// Milliseconds since UNIX epoch
    @objc dynamic var timestamp: Int = 0
    
    // MARK: - Setup

    convenience init(latitude: Double,
                  longitude: Double,
                  geoURI: String,
                  desc: String? = nil,
                  beaconInfoEventId: String,
                  timestamp: Int) {
        
        // https://www.mongodb.com/docs/realm-legacy/docs/swift/latest/#adding-custom-initializers-to-object-subclasses
        self.init() //Please note this says 'self' and not 'super'
        
        self.latitude = latitude
        self.longitude = longitude
        self.geoURI = geoURI
        self.desc = desc
        self.beaconInfoEventId = beaconInfoEventId
        self.timestamp = timestamp
    }
}

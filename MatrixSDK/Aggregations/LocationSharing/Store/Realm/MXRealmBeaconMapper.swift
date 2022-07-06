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

/// Enables to convert `MXBeaconInfoSummary` to `MXRealmBeaconInfoSummary` and make the opposite.
class MXRealmBeaconMapper {
    
    // MARK: - Properties
    
    private unowned let session: MXSession
    
    // MARK: - Setup
    
    init(session: MXSession) {
        self.session = session
    }
    
    // MARK: - Public
    
    func realmBeaconInfoSummary(from beaconInfoSummary: MXBeaconInfoSummary) -> MXRealmBeaconInfoSummary{
     
        let beaconInfo = beaconInfoSummary.beaconInfo
        
        let realmBeaconInfo = MXRealmBeaconInfo(userId: beaconInfo.userId,
                                                roomId: beaconInfo.roomId,
                                                desc: beaconInfo.desc,
                                                timeout: Int(beaconInfo.timeout),
                                                isLive: beaconInfo.isLive,
                                                assetTypeRawValue: Int(beaconInfo.assetType.rawValue),
                                                timestamp: Int(beaconInfo.timestamp),
                                                originalEventId: beaconInfo.originalEvent?.eventId)
        
        var realmLastBeacon: MXRealmBeacon?
        
        if let lastBeacon = beaconInfoSummary.lastBeacon {
            
            realmLastBeacon = MXRealmBeacon(latitude: lastBeacon.location.latitude,
                                            longitude: lastBeacon.location.longitude,
                                            geoURI:lastBeacon.location.geoURI,
                                            desc: lastBeacon.location.desc,
                                            beaconInfoEventId: lastBeacon.beaconInfoEventId,
                                            timestamp: Int(lastBeacon.timestamp))
        }
        
        return MXRealmBeaconInfoSummary(identifier:
                                            beaconInfoSummary.id,
                                        userId: beaconInfoSummary.userId,
                                        roomId: beaconInfoSummary.roomId,
                                        deviceId: beaconInfoSummary.deviceId,
                                        beaconInfo: realmBeaconInfo,
                                        lastBeacon: realmLastBeacon)
    }
    
    func beaconInfoSummary(from realmBeaconInfoSummary: MXRealmBeaconInfoSummary) -> MXBeaconInfoSummary? {
                
        let orginalEvent: MXEvent
        
        let eventId = realmBeaconInfoSummary.identifier
        let roomId = realmBeaconInfoSummary.roomId
        
        if let event = session.store.event(withEventId: eventId, inRoom: roomId) {
            orginalEvent = event
        } else {
            let fakeEvent = MXEvent()
            fakeEvent.eventId = eventId
            orginalEvent = fakeEvent
        }
        
        guard let realmBeaconInfo = realmBeaconInfoSummary.beaconInfo else {
            return nil
        }
        
        let beaconInfo = MXBeaconInfo(userId: realmBeaconInfo.userId, roomId: realmBeaconInfo.roomId, description: realmBeaconInfo.desc, timeout: UInt64(realmBeaconInfo.timeout), isLive: realmBeaconInfo.isLive, timestamp: UInt64(realmBeaconInfo.timestamp), originalEvent: orginalEvent)
                
        let beaconInfoSummary = MXBeaconInfoSummary(identifier: realmBeaconInfoSummary.identifier, userId: realmBeaconInfoSummary.userId, roomId: realmBeaconInfoSummary.roomId, beaconInfo: beaconInfo)
        
        if let deviceId = realmBeaconInfoSummary.deviceId {
            beaconInfoSummary.updateWithDeviceId(deviceId)
        }

        if let realmLastBeacon = realmBeaconInfoSummary.lastBeacon {
            let lastBeacon = MXBeacon(latitude: realmLastBeacon.latitude, longitude: realmLastBeacon.longitude, description: realmLastBeacon.desc, timestamp: UInt64(realmLastBeacon.timestamp), beaconInfoEventId: realmLastBeacon.beaconInfoEventId)
            
            beaconInfoSummary.updateWithLastBeacon(lastBeacon)
        }
        
        return beaconInfoSummary
    }
}

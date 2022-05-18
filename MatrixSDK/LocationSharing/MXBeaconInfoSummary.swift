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

/// MXBeaconInfoSummary summarize live location sharing for a user sharing his location in a room.
@objcMembers
public class MXBeaconInfoSummary: NSObject, MXBeaconInfoSummaryProtocol {
    
    // MARK: - Properties
    
    public let id: String
    public let userId: String
    public let roomId: String
    public private(set) var deviceId: String?
    public private(set) var beaconInfo: MXBeaconInfo
    public private(set) var lastBeacon: MXBeacon?
        
    public var expiryTimestamp: UInt64 {
        return beaconInfo.timestamp + beaconInfo.timeout
    }
    
    public var hasExpired: Bool {
        return Date().timeIntervalSince1970 * 1000 > TimeInterval(expiryTimestamp)
    }
    
    public var hasStopped: Bool {
        return !beaconInfo.isLive
    }
    
    public var isActive: Bool {
        return !(self.hasStopped || self.hasExpired)
    }
    
    // MARK: - Setup
    
    public convenience init?(beaconInfo: MXBeaconInfo) {
        
        guard let identifier = beaconInfo.originalEvent?.eventId, let userId = beaconInfo.userId, let roomId = beaconInfo.roomId else {
            return nil
        }
        self.init(identifier: identifier, userId: userId, roomId: roomId, beaconInfo: beaconInfo)
    }
    
    public init(identifier: String,
                userId: String,
                roomId: String,
                beaconInfo: MXBeaconInfo) {
        self.id = identifier
        self.userId = userId
        self.roomId = roomId
        self.beaconInfo = beaconInfo
        
        super.init()
    }
    
    // MARK: - Internal
    
    @discardableResult
    func updateWithBeaconInfo(_ beaconInfo: MXBeaconInfo) -> Bool {
        
        guard let beaconInfoEventId = beaconInfo.originalEvent?.eventId else {
            return false
        }
        
        guard beaconInfo.userId == self.userId else {
            return false
        }
        
        if beaconInfoEventId == self.id {
            self.beaconInfo = beaconInfo
            return true
        } else if beaconInfoEventId != self.id
                && self.beaconInfo.isLive == true
                && beaconInfo.isLive == false
                && beaconInfo.desc == self.beaconInfo.desc
                && beaconInfo.timeout == self.beaconInfo.timeout
                && beaconInfo.timestamp == self.beaconInfo.timestamp {
            
            // Beacon info with a different event id is only allowed when the beacon info is representing the stop state
            
            // Update current beacon info with `isLive` property to false
            self.beaconInfo = self.beaconInfo.stopped()
            
            return true
        }

        return false
    }
    
    @discardableResult
    func updateWithLastBeacon(_ beacon: MXBeacon) -> Bool {
        guard beacon.beaconInfoEventId == self.id else {
            return false
        }
        
        self.lastBeacon = beacon
        
        return true
    }
    
    /// Only set the device id after the beacon start if needed for current user only.
    /// There is no reason to change it twice.
    @discardableResult
    func updateWithDeviceId(_ deviceId: String) -> Bool {
        guard self.deviceId == nil else {
            return false
        }
        self.deviceId = deviceId
        return true
    }
}

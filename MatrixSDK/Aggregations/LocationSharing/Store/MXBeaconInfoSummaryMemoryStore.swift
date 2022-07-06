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

/// MXBeaconInfoSummary memory store
public class MXBeaconInfoSummaryMemoryStore: NSObject, MXBeaconInfoSummaryStoreProtocol {
    
    // MARK: - Properties
    
    private var beaconInfoSummaries: [String: [MXBeaconInfoSummary]] = [:]
    
    // MARK: - Public
    
    public func addOrUpdateBeaconInfoSummary(_ beaconInfoSummary: MXBeaconInfoSummary, inRoomWithId roomId: String) {
        
        var beaconInfoSummaries = self.getAllBeaconInfoSummaries(inRoomWithId: roomId)
        
        let existingIndex = beaconInfoSummaries.firstIndex { summary in
            return summary.id == beaconInfoSummary.id
        }
        
        if let existingIndex = existingIndex {
            beaconInfoSummaries[existingIndex] = beaconInfoSummary
        } else {
            beaconInfoSummaries.append(beaconInfoSummary)
        }
        
        self.beaconInfoSummaries[roomId] = beaconInfoSummaries
    }
    
    public func getBeaconInfoSummary(withIdentifier identifier: String, inRoomWithId roomId: String) -> MXBeaconInfoSummary? {
        guard let roomBeaconInfoSummaries = self.beaconInfoSummaries[roomId] else {
            return nil
        }
        
        return roomBeaconInfoSummaries.first { beaconInfoSummary in
            return beaconInfoSummary.id == identifier
        }
    }
    
    public func getBeaconInfoSummaries(for userId: String, inRoomWithId roomId: String) -> [MXBeaconInfoSummary] {
        
        guard let roomBeaconInfoSummaries = self.beaconInfoSummaries[roomId] else {
            return []
        }
        
        return roomBeaconInfoSummaries.filter { beaconInfoSummary in
            beaconInfoSummary.userId == userId
        }
    }
    
    public func getAllBeaconInfoSummaries(forUserId userId: String) -> [MXBeaconInfoSummary] {
        
        var userSummaries: [MXBeaconInfoSummary] = []
        
        for (_, roomSummaries) in self.beaconInfoSummaries {
            
            let userRoomSummaries = roomSummaries.filter { summary in
                summary.userId == userId
            }
            
            userSummaries.append(contentsOf: userRoomSummaries)
        }
        
        return userSummaries
    }
    
    public func getAllBeaconInfoSummaries(inRoomWithId roomId: String) -> [MXBeaconInfoSummary] {
        return self.beaconInfoSummaries[roomId] ?? []
    }
    
    public func deleteBeaconInfoSummary(with identifier: String, inRoomWithId roomId: String) {
        
        guard let beaconInfoSummaries = self.beaconInfoSummaries[roomId] else {
            return
        }
        
        let updatedBeaconInfoSummaries =  beaconInfoSummaries.filter { summary in
            summary.id == identifier
        }
        
        self.beaconInfoSummaries[roomId] = updatedBeaconInfoSummaries
    }
    
    public func deleteAllBeaconInfoSummaries(inRoomWithId roomId: String) {
        self.beaconInfoSummaries[roomId] = nil
    }
    
    public func deleteAllBeaconInfoSummaries() {
        self.beaconInfoSummaries = [:]
    }
    
    public func getBeaconInfoSummary(withUserId userId: String,
                                     description: String?,
                                     timeout: UInt64,
                                     timestamp: UInt64,
                                     inRoomWithId roomId: String) -> MXBeaconInfoSummary? {
        
        let beaconInfoSummaries = self.getAllBeaconInfoSummaries(inRoomWithId: roomId)
        
        return beaconInfoSummaries.first { beaconInfoSummary in
            let beaconInfo = beaconInfoSummary.beaconInfo
            
            return beaconInfo.userId == userId
            && beaconInfo.desc == description
            && beaconInfo.timeout == timeout
            && beaconInfo.timestamp == timestamp
        }
    }
}


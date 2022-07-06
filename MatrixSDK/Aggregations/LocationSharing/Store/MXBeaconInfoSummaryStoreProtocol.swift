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

/// Represents MXBeaconInfoSummary store
@objc public protocol MXBeaconInfoSummaryStoreProtocol: AnyObject {
    
    /// Add or update a MXBeaconInfoSummary for a given room
    func addOrUpdateBeaconInfoSummary(_ beaconInfoSummary: MXBeaconInfoSummary, inRoomWithId roomId: String)
    
    /// Get a MXBeaconInfoSummary from his identifier in a given room. The identifier is the first beacon info event id.
    func getBeaconInfoSummary(withIdentifier identifier: String, inRoomWithId roomId: String) -> MXBeaconInfoSummary?
    
    /// Get a MXBeaconInfoSummary from exact property values
    func getBeaconInfoSummary(withUserId userId: String,
                              description: String?,
                              timeout: UInt64,
                              timestamp: UInt64,
                              inRoomWithId roomId: String) -> MXBeaconInfoSummary?
    
    
    /// Get all MXBeaconInfoSummary in a room for a user
    func getBeaconInfoSummaries(for userId: String, inRoomWithId roomId: String) -> [MXBeaconInfoSummary]
    
    /// Get all MXBeaconInfoSummary in a room
    func getAllBeaconInfoSummaries(inRoomWithId roomId: String) -> [MXBeaconInfoSummary]
    
    /// Get all MXBeaconInfoSummary for a user
    func getAllBeaconInfoSummaries(forUserId userId: String) -> [MXBeaconInfoSummary]
    
    /// Delete MXBeaconInfoSummary with given identifier in a room
    func deleteBeaconInfoSummary(with identifier: String, inRoomWithId: String)
    
    /// Delete all MXBeaconInfoSummary in a room
    func deleteAllBeaconInfoSummaries(inRoomWithId roomId: String)
    
    /// Delete all MXBeaconInfoSummary
    func deleteAllBeaconInfoSummaries()
}

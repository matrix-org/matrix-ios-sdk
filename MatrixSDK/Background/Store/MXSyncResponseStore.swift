// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

/// Protocol defining the storage for a sync response.
@objc public protocol MXSyncResponseStore: NSObjectProtocol {
    /// Open the store with the given credentials
    /// - Parameter credentials: Credentials
    func open(withCredentials credentials: MXCredentials)
    
    /// The sync token that generated the currenly stored `syncResponse`.
    var syncToken: String? { get set }
    
    /// Sync response object, currently stored in the store
    var syncResponse: MXSyncResponse? { get set }
    
    /// User account data
    var accountData: [AnyHashable : Any]? { get set }
    
    /// Fetch event in the store
    /// - Parameters:
    ///   - eventId: Event identifier to be fetched.
    ///   - roomId: Room identifier to be fetched.
    func event(withEventId eventId: String, inRoom roomId: String) -> MXEvent?
    
    /// Fetch room summary for an invited room. Just uses the data in syncResponse to guess the room display name
    /// - Parameter roomId: Room identifier to be fetched
    /// - Parameter summary: A room summary (if exists) which user had before a sync response
    func roomSummary(forRoomId roomId: String, using summary: MXRoomSummary?) -> MXRoomSummary?
    
    
    //    var syncResponsesByPrevBatch: [String] { get }
    //
    //    func markSyncResponseAsObsolete()
    //    var obsoleteSyncResponseIds: [String] { get }
    //
    //    func syncResponse(withId id: String) -> MXSyncResponse
    
    
    /// Delete all data in the store
    func deleteData()
}

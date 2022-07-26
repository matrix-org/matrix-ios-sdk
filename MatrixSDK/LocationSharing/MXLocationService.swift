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

/// MXLocationService handles live location sharing
/// Note: Cannot use a protocol because of Objective-C compatibility
@objcMembers
public class MXLocationService: NSObject {
    
    // MARK: - Properties
    
    private unowned let session: MXSession
    
    // MARK: - Setup
    
    public init(session: MXSession) {
        self.session = session
    }
    
    // MARK: - Public
    
    // MARK: User live location
    
    /// Start live location sharing for current user
    /// - Parameters:
    ///   - roomId: The roomId where the location should be shared
    ///   - description: The location description
    ///   - timeout: The location sharing duration in milliseconds
    ///   - completion: A closure called when the operation completes. Provides the event id of the event generated on the home server on success.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func startUserLocationSharing(withRoomId roomId: String,
                                         description: String?,
                                         timeout: TimeInterval,
                                         completion: @escaping (MXResponse<String>) -> Void) -> MXHTTPOperation? {
        
        var operation: MXHTTPOperation?
        
        // Stop existing beacon if needed
        // Note: Only one live beacon per user per room is allowed
        operation = self.stopUserLocationSharing(inRoomWithId: roomId) { stopLocationSharingResponse in
            
            operation = self.sendBeaconInfoEvent(withRoomId: roomId, description: description, timeout: timeout) { response in
                
                switch response {
                case .success(let eventId):
                    var listener: AnyObject?
                    
                    // Update corresponding beacon info summary with current device id
                    listener = self.session.aggregations.beaconAggregations.listenToBeaconInfoSummaryUpdateInRoom(withId: roomId) { [weak self] beaconInfoSummary in
                        
                        guard let self = self else {
                            return
                        }
                        
                        if beaconInfoSummary.id == eventId {
                            if let listener = listener {
                                self.session.aggregations.removeListener(listener)
                            }
                           
                            if let myDeviceId = self.session.myDeviceId {
                                self.session.aggregations.beaconAggregations.updateBeaconInfoSummary(with: eventId, deviceId: myDeviceId, inRoomWithId: roomId)
                            }
                        }
                    }
                case .failure:
                    break
                }
                
                completion(response)
            }
        }
        
        return operation
    }
    
    @discardableResult
    
    /// Stop user location sharing in a room for a dedicated beacon info
    /// - Parameters:
    ///   - beaconInfoEventId: The beacon info event id that initiates the location sharing
    ///   - roomId: The roomId where the location should be stopped
    ///   - completion: A closure called when the operation completes.
    /// - Returns: a `MXHTTPOperation` instance.
    public func stopUserLocationSharing(withBeaconInfoEventId beaconInfoEventId: String,
                                        roomId: String,
                                        completion: @escaping (MXResponse<String>) -> Void) -> MXHTTPOperation? {
        
        guard let myUserId = self.session.myUserId else {
            completion(.failure(MXLocationServiceError.missingUserId))
            return nil
        }
        
        guard let beaconInfoSummary = self.session.aggregations.beaconAggregations.beaconInfoSummary(for: beaconInfoEventId, inRoomWithId: roomId) else {
            completion(.failure(MXLocationServiceError.beaconInfoNotFound))
            return nil
        }
        
        guard beaconInfoSummary.userId == myUserId else {
            completion(.failure(MXLocationServiceError.beaconInfoDoNotBelongToUser))
            return nil
        }
        
        guard beaconInfoSummary.hasStopped == false else {
            completion(.failure(MXLocationServiceError.beaconInfoAlreadyStopped))
            return nil
        }
        
        let initialBeaconInfo = beaconInfoSummary.beaconInfo
        
        // A new beacon info event is emitted with the same content as the original one execpt isLive = false
        let newBeaconInfo = MXBeaconInfo(userId: nil,
                                         roomId: nil,
                                         description: initialBeaconInfo.desc,
                                         timeout: initialBeaconInfo.timeout,
                                         isLive: false,
                                         timestamp: initialBeaconInfo.timestamp)
        
        return self.sendBeaconInfo(newBeaconInfo, inRoomWithId: roomId, completion: completion)
    }
    
    /// Stop user location sharing in a room
    /// NOTE: Only stop last user beacon info at the moment
    /// - Parameters:
    ///   - roomId: The roomId where the location should be stopped
    ///   - completion: A closure called when the operation completes.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func stopUserLocationSharing(inRoomWithId roomId: String,
                                        completion: @escaping (MXResponse<String>) -> Void) -> MXHTTPOperation? {
        guard let myUserId = self.session.myUserId else {
            completion(.failure(MXLocationServiceError.missingUserId))
            return nil
        }
        
        let userBeaconInfoSummaries = self.getLiveBeaconInfoSummaries(for: myUserId, inRoomWithId: roomId).sorted(by: { $0.expiryTimestamp < $1.expiryTimestamp })
        
        guard let lastBeaconInfoSummary = userBeaconInfoSummaries.last else {
            completion(.failure(MXLocationServiceError.beaconInfoNotFound))
            return nil
        }
        
        return self.stopUserLocationSharing(withBeaconInfoEventId: lastBeaconInfoSummary.id, roomId: roomId, completion: completion)
    }
        
    /// Send a beacon for an attached beacon info in a room
    /// - Parameters:
    ///   - beaconInfoEventId: The associated beacon info event id
    ///   - latitude: Coordinate latitude
    ///   - longitude: Coordinate longitude
    ///   - description: Beacon description. nil by default.
    ///   - threadId: the id of the thread to send the message. nil by default.
    ///   - roomId: The room id
    ///   - localEcho: a pointer to an MXEvent object.
    ///   - completion: A closure called when the operation completes. Provides the event id of the event generated on the home server on success.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func sendLocation(withBeaconInfoEventId beaconInfoEventId: String,
                             latitude: Double,
                             longitude: Double,
                             description: String? = nil,
                             threadId: String? = nil,
                             inRoomWithId roomId: String,
                             localEcho: inout MXEvent?,
                             completion: @escaping (MXResponse<String?>) -> Void) -> MXHTTPOperation? {

        guard let myUserId = self.session.myUserId else {
            completion(.failure(MXLocationServiceError.missingUserId))
            return nil
        }
        
        guard let beaconInfoSummary = self.session.aggregations.beaconAggregations.beaconInfoSummary(for: beaconInfoEventId, inRoomWithId: roomId) else {
            completion(.failure(MXLocationServiceError.beaconInfoNotFound))
            return nil
        }
        
        guard beaconInfoSummary.userId == myUserId else {
            completion(.failure(MXLocationServiceError.beaconInfoDoNotBelongToUser))
            return nil
        }
        
        guard beaconInfoSummary.hasStopped == false else {
            completion(.failure(MXLocationServiceError.beaconInfoAlreadyStopped))
            return nil
        }
        
        guard beaconInfoSummary.hasExpired == false else {
            completion(.failure(MXLocationServiceError.beaconInfoExpired))
            return nil
        }
        
        return self.sendBeacon(withBeaconInfoEventId: beaconInfoEventId, latitude: latitude, longitude: longitude, description: description, threadId: threadId, inRoomWithId: roomId, localEcho: &localEcho, completion: completion)
    }
    
    /// Check if the current user is sharing is location in a room
    /// - Parameter roomId: The room id
    /// - Returns: true if the user if sharing is location
    public func isCurrentUserSharingLocation(inRoomWithId roomId: String) -> Bool {
        
        guard let myUserId = self.session.myUserId else {
            return false
        }
        
        return self.getLiveBeaconInfoSummaries(for: myUserId, inRoomWithId: roomId).isEmpty == false
    }
    
    /// Check if the current user is sharing is location in a room and the sharing is not expired
    /// - Parameter roomId: The room id
    /// - Returns: true if the user if sharing is location
    public func isCurrentUserSharingActiveLocation(inRoomWithId roomId: String) -> Bool {
        
        guard let myUserId = self.session.myUserId else {
            return false
        }
        
        return self.getActiveBeaconInfoSummaries(for: myUserId, inRoomWithId: roomId).isEmpty == false
    }
    
    // MARK: Beacon info
    
    /// Get all beacon info in a room
    /// - Parameters:
    ///   - roomId: The room id of the room
    ///   - completion: Closure called when beacon fetching as ended. Give beacon info array as a result.
    public func getAllBeaconInfo(inRoomWithId roomId: String, completion: @escaping ([MXBeaconInfo]) -> Void) {
        
        guard let room = self.session.room(withRoomId: roomId) else {
            completion([])
            return
        }
        
        room.state { roomState in
            completion(roomState?.beaconInfos ?? [])
        }
    }
    
    /// Get all beacon info of a user in a room
    /// - Parameters:
    ///   - userId: The user id
    ///   - roomId: The room id
    ///   - completion: Closure called when beacon fetching as ended. Give beacon info array as a result.
    public func getAllBeaconInfo(forUserId userId: String, inRoomWithId roomId: String, completion: @escaping ([MXBeaconInfo]) -> Void) {
        self.getAllBeaconInfo(inRoomWithId: roomId) { allBeaconInfo in
            
            let userBeaconInfoList = allBeaconInfo.filter( { return $0.userId == userId })
            completion(userBeaconInfoList)
        }
    }
    
    public func getAllBeaconInfoForCurrentUser(inRoomWithId roomId: String, completion: @escaping ([MXBeaconInfo]) -> Void) {
        
        guard let myUserId = self.session.myUserId else {
            completion([])
            return
        }
        
        self.getAllBeaconInfo(forUserId: myUserId, inRoomWithId: roomId, completion: completion)
    }
    
    /// Get stopped beacon info from the orginal start beacon info event id
    public func getStoppedBeaconInfo(for beaconInfoEventId: String, inRoomWithId roomId: String, completion: @escaping (MXBeaconInfo?) -> Void) {
        
        guard let beaconInfoSummary = self.session.aggregations.beaconAggregations.beaconInfoSummary(for: beaconInfoEventId, inRoomWithId: roomId) else {
            completion(nil)
            return
        }
        
        // Do not go further is the beacon info is not stopped
        guard beaconInfoSummary.beaconInfo.isLive == false else {
            completion(nil)
            return
        }
        
        let originalBeaconInfo = beaconInfoSummary.beaconInfo
        
        self.session.locationService.getAllBeaconInfo(inRoomWithId: beaconInfoSummary.roomId) { beaconInfos in
            
            let stoppedBeaconInfo = beaconInfos.first { beaconInfo in
                return beaconInfo.isLive == false
                && beaconInfo.userId == originalBeaconInfo.userId
                && beaconInfo.desc == originalBeaconInfo.desc
                && beaconInfo.timeout == originalBeaconInfo.timeout
                && beaconInfo.timestamp == originalBeaconInfo.timestamp
            }
            
            completion(stoppedBeaconInfo)
        }
    }
    
    // MARK: - Beacon info summary
    
    /// Get all beacon info summaries in a room
    /// - Parameters:
    ///   - roomId: The room id of the room
    /// - Returns: Room beacon info summaries
    public func getBeaconInfoSummaries(inRoomWithId roomId: String) -> [MXBeaconInfoSummaryProtocol] {
        return self.session.aggregations.beaconAggregations.getBeaconInfoSummaries(inRoomWithId: roomId)
    }
    
    /// Get all beacon info summaries in a room for a user
    /// - Parameters:
    ///   - roomId: The room id of the room
    ///   - userId: The user id
    /// - Returns: Room beacon info summaries
    public func getBeaconInfoSummaries(for userId: String, inRoomWithId roomId: String) -> [MXBeaconInfoSummaryProtocol] {
        return self.session.aggregations.beaconAggregations.getBeaconInfoSummaries(for: userId, inRoomWithId: roomId)
    }
    
    /// Get all beacon info summaries for a user
    /// - Parameters:
    ///   - userId: The user id
    /// - Returns: Room beacon info summaries
    public func getBeaconInfoSummaries(for userId: String) -> [MXBeaconInfoSummaryProtocol] {
        return self.session.aggregations.beaconAggregations.getBeaconInfoSummaries(for: userId)
    }
    
    /// Get all live beacon info summaries in a room
    /// - Parameters:
    ///   - roomId: The room id of the room
    /// - Returns: Room live beacon info summaries
    public func getLiveBeaconInfoSummaries(inRoomWithId roomId: String) -> [MXBeaconInfoSummaryProtocol] {
        
        let beaconInfoSummaries = self.getBeaconInfoSummaries(inRoomWithId: roomId)
        return beaconInfoSummaries.filter { beaconInfoSummary in
            return beaconInfoSummary.beaconInfo.isLive
        }
    }
    
    /// Get all beacon info summaries in a room for a user
    /// - Parameters:
    ///   - userId: The user id
    ///   - roomId: The room id of the room
    /// - Returns: Room beacon info summaries
    public func getLiveBeaconInfoSummaries(for userId: String, inRoomWithId roomId: String) -> [MXBeaconInfoSummaryProtocol] {
        
        let beaconInfoSummaries = self.getLiveBeaconInfoSummaries(inRoomWithId: roomId)
        return beaconInfoSummaries.filter { beaconInfoSummary in
            return beaconInfoSummary.userId == userId
        }
    }
    
    /// Get all active (live and not expired) beacon info summaries in a room.
    /// - Parameters:
    ///   - roomId: The room id of the room
    /// - Returns: Room live beacon info summaries
    public func getActiveBeaconInfoSummaries(inRoomWithId roomId: String) -> [MXBeaconInfoSummaryProtocol] {
        
        let beaconInfoSummaries = self.getBeaconInfoSummaries(inRoomWithId: roomId)
        return beaconInfoSummaries.filter { beaconInfoSummary in
            return beaconInfoSummary.isActive
        }
    }
    
    /// Get all active (live and not expired) beacon info summaries in a room for a user.
    /// - Parameters:
    ///   - userId: The user id
    ///   - roomId: The room id of the room
    /// - Returns: Room live beacon info summaries
    public func getActiveBeaconInfoSummaries(for userId: String, inRoomWithId roomId: String) -> [MXBeaconInfoSummaryProtocol] {
        
        let beaconInfoSummaries = self.getBeaconInfoSummaries(for: userId, inRoomWithId: roomId)
        return beaconInfoSummaries.filter { beaconInfoSummary in
            return beaconInfoSummary.isActive
        }
    }
    
    public func isSomeoneSharingLiveLocation(inRoomWithId roomId: String) -> Bool {
        return self.getLiveBeaconInfoSummaries(inRoomWithId: roomId).isEmpty == false
    }
    
    public func isSomeoneSharingActiveLocation(inRoomWithId roomId: String) -> Bool {
        return self.getActiveBeaconInfoSummaries(inRoomWithId: roomId).isEmpty == false
    }
    
    // MARK: - Private
        
    private func sendBeaconInfoEvent(withRoomId roomId: String,
                                     description: String?,
                                     timeout: TimeInterval,
                                     completion: @escaping (MXResponse<String>) -> Void) -> MXHTTPOperation? {
        
        let beaconInfo = MXBeaconInfo(description: description,
                                      timeout: UInt64(timeout),
                                      isLive: true)
        
        return self.sendBeaconInfo(beaconInfo, inRoomWithId: roomId, completion: completion)
    }
    
    private func sendBeaconInfo(_ beaconInfo: MXBeaconInfo,
                                inRoomWithId roomId: String,
                                completion: @escaping (MXResponse<String>) -> Void) -> MXHTTPOperation? {
        
        guard let userId = self.session.myUserId else {
            completion(.failure(MXLocationServiceError.missingUserId))
            return nil
        }
                
        let stateKey = userId
                
        guard let eventContent = beaconInfo.jsonDictionary() as? [String : Any] else {
            completion(.failure(MXLocationServiceError.unknown))
            return nil
        }
        
        return self.session.matrixRestClient.sendStateEvent(toRoom: roomId, eventType: .beaconInfo, content: eventContent, stateKey: stateKey) { response in
            completion(response)
        }
    }
    
    @discardableResult
    private func sendBeacon(withBeaconInfoEventId beaconInfoEventId: String,
                            latitude: Double,
                            longitude: Double,
                            description: String? = nil,
                            threadId: String? = nil,
                            inRoomWithId roomId: String,
                            localEcho: inout MXEvent?,
                            completion: @escaping (MXResponse<String?>) -> Void) -> MXHTTPOperation? {

        guard let room = self.session.room(withRoomId: roomId) else {
            completion(.failure(MXLocationServiceError.roomNotFound))
            return nil
        }
        
        let beacon = MXBeacon(latitude: latitude, longitude: longitude, description: description, beaconInfoEventId: beaconInfoEventId)
        
        guard let eventContent = beacon.jsonDictionary() as? [String: Any] else {
            completion(.failure(MXLocationServiceError.unknown))
            return nil
        }

        return room.sendEvent(.beacon, content: eventContent, threadId: threadId, localEcho: &localEcho, completion: completion)
    }
}

// MARK: - Objective-C
extension MXLocationService {
    
    /// Start live location sharing for current user
    /// - Parameters:
    ///   - roomId: The roomId where the location should be shared
    ///   - description: The location description
    ///   - timeout: The location sharing duration
    ///   - success: A closure called when the operation is complete. Provides the event id of the event generated on the home server on success.
    ///   - failure: A closure called  when the operation fails.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func startUserLocationSharing(withRoomId roomId: String,
                                         description: String,
                                         timeout: TimeInterval,
                                         success: @escaping (String) -> Void,
                                         failure: @escaping (Error) -> Void) -> MXHTTPOperation? {
        return self.sendBeaconInfoEvent(withRoomId: roomId, description: description, timeout: timeout) { (response) in
            uncurryResponse(response, success: success, failure: failure)
        }
    }
}

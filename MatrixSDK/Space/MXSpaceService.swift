// 
// Copyright 2021 The Matrix.org Foundation C.I.C
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

/// MXSpaceService error
public enum MXSpaceServiceError: Int, Error {
    case spaceNotFound
    case unknown
}

extension MXSpaceServiceError: CustomNSError {
    public static let errorDomain = "org.matrix.sdk.spaceService"

    public var errorCode: Int {
        return Int(rawValue)
    }

    public var errorUserInfo: [String: Any] {
        return [:]
    }
}

/// MXSpaceService enables to handle spaces.
@objcMembers
public class MXSpaceService: NSObject {
    
    // MARK: - Properties
    
    private unowned let session: MXSession
    
    private lazy var stateEventBuilder: MXRoomInitialStateEventBuilder = {
        return MXRoomInitialStateEventBuilder()
    }()
    
    private let roomTypeMapper: MXRoomTypeMapper
    
    private let processingQueue: DispatchQueue
    private let completionQueue: DispatchQueue
    
    // MARK: - Setup
    
    public init(session: MXSession) {
        self.session = session
        self.roomTypeMapper = MXRoomTypeMapper(defaultRoomType: .room)
        self.processingQueue = DispatchQueue(label: "org.matrix.sdk.MXSpaceService.processingQueue", attributes: .concurrent)
        self.completionQueue = DispatchQueue.main
    }
    
    // MARK: - Public
    
    /// Create a space.
    /// - Parameters:
    ///   - parameters: The parameters for space creation.
    ///   - completion: A closure called when the operation completes.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func createSpace(with parameters: MXSpaceCreationParameters, completion: @escaping (MXResponse<MXSpace>) -> Void) -> MXHTTPOperation {
        return self.session.createRoom(parameters: parameters) { (response) in
            switch response {
            case .success(let room):
                let space: MXSpace = MXSpace(room: room)
                completion(.success(space))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Create a space shortcut.
    /// - Parameters:
    ///   - name: The space name.
    ///   - topic: The space topic.
    ///   - isPublic: true to indicate to use public chat presets and join the space without invite or false to use private chat presets and join the space on invite.
    ///   - completion: A closure called when the operation completes.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func createSpace(withName name: String, topic: String?, isPublic: Bool, completion: @escaping (MXResponse<MXSpace>) -> Void) -> MXHTTPOperation {
        let parameters = MXSpaceCreationParameters()
        parameters.name = name
        parameters.topic = topic
        parameters.preset = isPublic ? kMXRoomPresetPublicChat : kMXRoomPresetPrivateChat
        
        if isPublic {
            let guestAccessStateEvent = self.stateEventBuilder.buildGuestAccessEvent(withAccess: .canJoin)
                                    
            let historyVisibilityStateEvent = self.stateEventBuilder.buildHistoryVisibilityEvent(withVisibility: .worldReadable)
            
            parameters.addOrUpdateInitialStateEvent(guestAccessStateEvent)
            parameters.addOrUpdateInitialStateEvent(historyVisibilityStateEvent)
        }
        
        return self.createSpace(with: parameters, completion: completion)
    }
    
    /// Get a space from a roomId.
    /// - Parameter spaceId: The id of the space.
    /// - Returns: A MXSpace with the associated roomId or null if room type is not space.
    public func getSpace(withId spaceId: String) -> MXSpace? {
        let room = self.session.room(withRoomId: spaceId)
        return room?.toSpace()
    }
        
    /// Get the space children informations of a given space from the server.
    /// - Parameters:
    ///   - spaceId: The room id of the queried space.
    ///   - parameters: Space children request parameters.
    ///   - completion: A closure called when the operation completes.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func getSpaceChildrenForSpace(withId spaceId: String,
                                         parameters: MXSpaceChildrenRequestParameters?,
                                         completion: @escaping (MXResponse<MXSpaceChildrenSummary>) -> Void) -> MXHTTPOperation {
        return self.session.matrixRestClient.getSpaceChildrenForSpace(withId: spaceId, parameters: parameters) { (response) in
            switch response {
            case .success(let spaceChildrenResponse):
                self.processingQueue.async { [weak self] in
                    guard let self = self else {
                        return
                    }
                    
                    guard let rooms = spaceChildrenResponse.rooms else {
                        // We should have at least one room for the requested space
                        self.completionQueue.async {
                            completion(.failure(MXSpaceServiceError.spaceNotFound))
                        }
                        return
                    }

                    guard let rootSpaceChildSummaryResponse = rooms.first(where: { spaceResponse -> Bool in
                        return spaceResponse.roomId == spaceId
                    }) else {
                        // Fail to find root child. We should have at least one room for the requested space
                        self.completionQueue.async {
                            completion(.failure(MXSpaceServiceError.spaceNotFound))
                        }
                        return
                    }

                    // Build the queried space summary
                    let spaceSummary = self.createRoomSummary(with: rootSpaceChildSummaryResponse)

                    // Build the child summaries of the queried space
                    let childInfos = self.spaceChildInfos(from: spaceChildrenResponse, excludedSpaceId: spaceId)

                    let spaceChildrenSummary = MXSpaceChildrenSummary(spaceSummary: spaceSummary, childInfos: childInfos)

                    self.completionQueue.async {
                        completion(.success(spaceChildrenSummary))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Private
    
    private func createRoomSummary(with spaceChildSummaryResponse: MXSpaceChildSummaryResponse) -> MXRoomSummary {
        
        let roomId = spaceChildSummaryResponse.roomId
        let roomTypeString = spaceChildSummaryResponse.roomType
                
        let roomSummary: MXRoomSummary = MXRoomSummary(roomId: roomId, andMatrixSession: nil)
        roomSummary.roomTypeString = roomTypeString
        roomSummary.roomType = self.roomTypeMapper.roomType(from: roomTypeString)
        
        let joinedMembersCount = UInt(spaceChildSummaryResponse.numJoinedMembers)
        
        let membersCount = MXRoomMembersCount()
        membersCount.joined = joinedMembersCount
        membersCount.members = joinedMembersCount
        
        roomSummary.membersCount = membersCount
        roomSummary.displayname = spaceChildSummaryResponse.name
        roomSummary.topic = spaceChildSummaryResponse.topic
        roomSummary.avatar = spaceChildSummaryResponse.avatarUrl
        roomSummary.isEncrypted = false
                                
        return roomSummary
    }
    
    private func spaceChildInfos(from spaceChildrenResponse: MXSpaceChildrenResponse, excludedSpaceId: String) -> [MXSpaceChildInfo] {
        guard let spaceChildSummaries = spaceChildrenResponse.rooms else {
            return []
        }
        
        let childInfos: [MXSpaceChildInfo] = spaceChildSummaries.compactMap { (spaceChildSummaryResponse) -> MXSpaceChildInfo? in
            
            let spaceId = spaceChildSummaryResponse.roomId
            
            guard spaceId != excludedSpaceId else {
                return nil
            }
            
            let childStateEvent = spaceChildrenResponse.events?.first(where: { (event) -> Bool in
                return event.stateKey == spaceId && event.eventType == .spaceChild
            })
                        
            return self.createSpaceChildInfo(with: spaceChildSummaryResponse, and: childStateEvent)
        }
        
        return childInfos
    }
    
    private func createSpaceChildInfo(with spaceChildSummaryResponse: MXSpaceChildSummaryResponse, and spaceChildStateEvent: MXEvent?) -> MXSpaceChildInfo {
        
        var spaceChildContent: MXSpaceChildContent?
        
        if let stateEventContent = spaceChildStateEvent?.content {
            spaceChildContent = MXSpaceChildContent(fromJSON: stateEventContent)
        }
        
        let roomTypeString = spaceChildSummaryResponse.roomType
        let roomType = self.roomTypeMapper.roomType(from: roomTypeString)
        
        return MXSpaceChildInfo(childRoomId: spaceChildSummaryResponse.roomId,
                         isKnown: true,
                         roomTypeString: roomTypeString,
                         roomType: roomType,
                         name: spaceChildSummaryResponse.name,
                         topic: spaceChildSummaryResponse.topic,
                         avatarUrl: spaceChildSummaryResponse.avatarUrl,
                         order: spaceChildContent?.order,
                         activeMemberCount: spaceChildSummaryResponse.numJoinedMembers,
                         autoJoin: spaceChildContent?.autoJoin ?? false,
                         viaServers: spaceChildContent?.via ?? [],
                         parentRoomId: spaceChildStateEvent?.roomId)
    }
}

// MARK: - Objective-C interface
extension MXSpaceService {
    
    /// Create a space.
    /// - Parameters:
    ///   - parameters: The parameters for space creation.
    ///   - success: A closure called when the operation is complete.
    ///   - failure: A closure called  when the operation fails.
    /// - Returns: a `MXHTTPOperation` instance.
    public func createSpace(with parameters: MXSpaceCreationParameters, success: @escaping (MXSpace) -> Void, failure: @escaping (Error) -> Void) -> MXHTTPOperation {
        return self.createSpace(with: parameters) { (response) in
            uncurryResponse(response, success: success, failure: failure)
        }
    }
    
    /// Create a space shortcut.
    /// - Parameters:
    ///   - name: The space name.
    ///   - topic: The space topic.
    ///   - isPublic: true to indicate to use public chat presets and join the space without invite or false to use private chat presets and join the space on invite.
    ///   - success: A closure called when the operation is complete.
    ///   - failure: A closure called  when the operation fails.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func createSpace(withName name: String, topic: String?, isPublic: Bool, success: @escaping (MXSpace) -> Void, failure: @escaping (Error) -> Void) -> MXHTTPOperation {
        return self.createSpace(withName: name, topic: topic, isPublic: isPublic) { (response) in
            uncurryResponse(response, success: success, failure: failure)
        }
    }
    
    /// Get the space children informations of a given space from the server.
    /// - Parameters:
    ///   - spaceId: The room id of the queried space.
    ///   - parameters: Space children request parameters.
    ///   - success: A closure called when the operation is complete.
    ///   - failure: A closure called  when the operation fails.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func getSpaceChildrenForSpace(withId spaceId: String,
                                         parameters: MXSpaceChildrenRequestParameters?,
                                         success: @escaping (MXSpaceChildrenSummary) -> Void, failure: @escaping (Error) -> Void) -> MXHTTPOperation {
        return self.getSpaceChildrenForSpace(withId: spaceId, parameters: parameters) { (response) in
            uncurryResponse(response, success: success, failure: failure)
        }
    }
}

// MARK: - Internal room additions
extension MXRoom {
    
    func toSpace() -> MXSpace? {
        guard self.summary.roomType == .space else {
            return nil
        }
        return MXSpace(room: self)
    }
}

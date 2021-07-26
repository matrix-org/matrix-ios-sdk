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

// MARK: - MXSpaceService errors
extension MXSpaceServiceError: CustomNSError {
    public static let errorDomain = "org.matrix.sdk.spaceService"

    public var errorCode: Int {
        return Int(rawValue)
    }

    public var errorUserInfo: [String: Any] {
        return [:]
    }
}

// MARK: - MXSpaceService notification constants
extension MXSpaceService {
    /// Posted once the graph of rooms is up and running
    public static let didBuildSpaceGraph = Notification.Name("MXSpaceServiceDidBuildSpaceGraph")
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
    
    private var spaces: [MXSpace] = []
    private var spacesPerId: [String : MXSpace] = [:]
    private var parentIdsPerRoomId: [String : Set<String>] = [:]
    
    private var rootSpaces: [MXSpace] = []
    private var orphanedRooms: [MXRoom] = []
    private var orphanedDirectRooms: [MXRoom] = []
    
    public var rootSpaceSummaries: [MXRoomSummary] {
        get {
            return rootSpaces.compactMap { space in
                return space.summary
            }
        }
    }
    
    // MARK: - Setup
    
    public init(session: MXSession) {
        self.session = session
        self.roomTypeMapper = MXRoomTypeMapper(defaultRoomType: .room)
        self.processingQueue = DispatchQueue(label: "org.matrix.sdk.MXSpaceService.processingQueue", attributes: .concurrent)
        self.completionQueue = DispatchQueue.main
    }
    
    // MARK: - Public
    
    /// Build the graph of rooms
    /// - Parameters:
    ///   - rooms: the complete list of rooms and spaces
    public func buildGraph(with rooms:[MXRoom]) {
        prepareData(with: rooms, index: 0, spaces: [], spacesPerId: [:], roomsPerId: [:], directRooms: [:]) { spaces, spacesPerId, roomsPerId, directRooms in
            MXLog.debug("\(spaces), \(spacesPerId), \(roomsPerId), \(directRooms)")
            var parentIdsPerRoomId: [String : Set<String>] = [:]
            spaces.forEach { space in
                space.updateChildSpaces(with: spacesPerId)
                space.updateChildDirectRooms(with: directRooms)
                space.childRoomIds.forEach { roomId in
                    var parentIds = parentIdsPerRoomId[roomId] ?? Set<String>()
                    parentIds.insert(space.spaceId)
                    parentIdsPerRoomId[roomId] = parentIds
                }
                space.childSpaces.forEach { childSpace in
                    var parentIds = parentIdsPerRoomId[childSpace.spaceId] ?? Set<String>()
                    parentIds.insert(space.spaceId)
                    parentIdsPerRoomId[childSpace.spaceId] = parentIds
                }
            }
            
            self.spaces = spaces
            self.spacesPerId = spacesPerId
            self.parentIdsPerRoomId = parentIdsPerRoomId
            self.rootSpaces = spaces.filter { space in
                return parentIdsPerRoomId[space.spaceId] == nil
            }
            self.orphanedRooms = self.session.rooms.filter { room in
                return !room.isDirect && parentIdsPerRoomId[room.roomId] == nil
            }
            self.orphanedDirectRooms = self.session.rooms.filter { room in
                return room.isDirect && parentIdsPerRoomId[room.roomId] == nil
            }
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: MXSpaceService.didBuildSpaceGraph, object: self)
            }
        }
    }
    
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
        return self.spacesPerId[spaceId]
    }
        
    /// Get the space children informations of a given space from the server.
    /// - Parameters:
    ///   - spaceId: The room id of the queried space.
    ///   - suggestedOnly: If `true`, return only child events and rooms where the `m.space.child` event has `suggested: true`.
    ///   - limit: Optional. A limit to the maximum number of children to return per space. `-1` for no limit
    ///   - completion: A closure called when the operation completes.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func getSpaceChildrenForSpace(withId spaceId: String,
                                         suggestedOnly: Bool,
                                         limit: Int?,
                                         completion: @escaping (MXResponse<MXSpaceChildrenSummary>) -> Void) -> MXHTTPOperation {
        return self.session.matrixRestClient.getSpaceChildrenForSpace(withId: spaceId, suggestedOnly: suggestedOnly, limit: limit) { (response) in
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
                    
                    self.spacesPerId[spaceId]?.lastSpaceChildrenSummary = spaceChildrenSummary

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
    
    private func prepareData(with rooms:[MXRoom], index: Int, spaces: [MXSpace], spacesPerId: [String : MXSpace], roomsPerId: [String : MXRoom], directRooms: [String: [MXRoom]], completion: @escaping (_ spaces: [MXSpace], _ spacesPerId: [String : MXSpace], _ roomsPerId: [String : MXRoom], _ directRooms: [String: [MXRoom]]) -> Void) {
        
        guard index < rooms.count else {
            completion(spaces, spacesPerId, roomsPerId, directRooms)
            return
        }
        
        let room = rooms[index]
        if let space = room.toSpace() {
            space.readChildRoomsAndMembers {
                var spaces = spaces
                spaces.append(space)
                var spacesPerId = spacesPerId
                spacesPerId[space.spaceId] = space
                
                self.prepareData(with: rooms, index: index+1, spaces: spaces, spacesPerId: spacesPerId, roomsPerId: roomsPerId, directRooms: directRooms, completion: completion)
            }
        } else if room.isDirect {
            room.members { response in
                guard let members = response.value as? MXRoomMembers else {
                    self.prepareData(with: rooms, index: index+1, spaces: spaces, spacesPerId: spacesPerId, roomsPerId: roomsPerId, directRooms: directRooms, completion: completion)
                    return
                }
                
                let membersId = members.members.compactMap({ roomMember in
                    return roomMember.userId != self.session.myUserId ? roomMember.userId : nil
                })
                
                var directRooms = directRooms
                membersId.forEach { memberId in
                    var rooms = directRooms[memberId] ?? []
                    rooms.append(room)
                    directRooms[memberId] = rooms
                }
                self.prepareData(with: rooms, index: index+1, spaces: spaces, spacesPerId: spacesPerId, roomsPerId: roomsPerId, directRooms: directRooms, completion: completion)
            }
        } else {
            var roomsPerId = roomsPerId
            roomsPerId[room.roomId] = room
            prepareData(with: rooms, index: index+1, spaces: spaces, spacesPerId: spacesPerId, roomsPerId: roomsPerId, directRooms: directRooms, completion: completion)
        }
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
    @objc public func createSpace(with parameters: MXSpaceCreationParameters, success: @escaping (MXSpace) -> Void, failure: @escaping (Error) -> Void) -> MXHTTPOperation {
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
    @objc public func createSpace(withName name: String, topic: String?, isPublic: Bool, success: @escaping (MXSpace) -> Void, failure: @escaping (Error) -> Void) -> MXHTTPOperation {
        return self.createSpace(withName: name, topic: topic, isPublic: isPublic) { (response) in
            uncurryResponse(response, success: success, failure: failure)
        }
    }
    
    /// Get the space children informations of a given space from the server.
    /// - Parameters:
    ///   - spaceId: The room id of the queried space.
    ///   - suggestedOnly: If `true`, return only child events and rooms where the `m.space.child` event has `suggested: true`.
    ///   - limit: Optional. A limit to the maximum number of children to return per space. `-1` for no limit
    ///   - completion: A closure called when the operation completes.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    @objc public func getSpaceChildrenForSpace(withId spaceId: String,
                                         suggestedOnly: Bool,
                                         limit: Int,
                                         success: @escaping (MXSpaceChildrenSummary) -> Void, failure: @escaping (Error) -> Void) -> MXHTTPOperation {
        return self.getSpaceChildrenForSpace(withId: spaceId, suggestedOnly: suggestedOnly, limit: limit) { (response) in
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

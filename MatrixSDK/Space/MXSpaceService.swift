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
    /// Posted once the first graph as been built or loaded
    public static let didInitialised = Notification.Name("MXSpaceServiceDidInitialised")

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
    private let sdkProcessingQueue: DispatchQueue
    private let completionQueue: DispatchQueue
    
    private var graph: MXSpaceGraphData = MXSpaceGraphData() {
        didSet {
            var spacesPerId: [String:MXSpace] = [:]
            self.graph.spaceRoomIds.forEach { spaceId in
                if let space = self.getSpace(withId: spaceId) {
                    spacesPerId[spaceId] = space
                }
            }
            self.spacesPerId = spacesPerId
        }
    }
    private var spacesPerId: [String:MXSpace] = [:]
    
    private var isGraphBuilding = false;
    
    public let notificationCounter: MXSpaceNotificationCounter
    
    public var rootSpaceSummaries: [MXRoomSummary] {
        return self.graph.rootSpaceIds.compactMap { spaceId in
            self.session.roomSummary(withRoomId: spaceId)
        }
    }
    
    public private(set) var needsUpdate: Bool = true
    
    public var graphUpdateEnabled = true
    
    private var sessionStateDidChangeObserver: Any?
    
    public var ancestorsPerRoomId: [String:Set<String>] {
        return graph.ancestorsPerRoomId
    }
    
    public private(set) var isInitialised = false {
        didSet {
            if !oldValue && isInitialised {
                self.completionQueue.async {
                    NotificationCenter.default.post(name: MXSpaceService.didInitialised, object: self)
                }
            }
        }
    }

    // MARK: - Setup
    
    public init(session: MXSession) {
        self.session = session
        self.notificationCounter = MXSpaceNotificationCounter(session: session)
        self.roomTypeMapper = MXRoomTypeMapper(defaultRoomType: .room)
        self.processingQueue = DispatchQueue(label: "org.matrix.sdk.MXSpaceService.processingQueue", attributes: .concurrent)
        self.completionQueue = DispatchQueue.main
        self.sdkProcessingQueue = DispatchQueue.main
        
        super.init()
        
        self.registerNotificationObservers()
    }
    
    deinit {
        unregisterNotificationObservers()
    }
    
    // MARK: - Public
    
    /// close the service and free all data
    public func close() {
        self.isGraphBuilding = true
        self.graph = MXSpaceGraphData()
        self.notificationCounter.close()
        self.isGraphBuilding = false
        self.completionQueue.async {
            NotificationCenter.default.post(name: MXSpaceService.didBuildSpaceGraph, object: self)
        }
    }
    
    /// Loads graph from the given store
    public func loadData() {
        self.processingQueue.async {
            let store = MXSpaceFileStore(userId: self.session.myUserId, deviceId: self.session.myDeviceId)
            if let loadedGraph = store.loadSpaceGraphData() {
                self.graph = loadedGraph

                self.completionQueue.async {
                    self.isInitialised = true
                    self.notificationCounter.computeNotificationCount()
                    NotificationCenter.default.post(name: MXSpaceService.didBuildSpaceGraph, object: self)
                }
            }
        }
    }
    
    /// Allows to know if a given room is a descendant of a given space
    /// - Parameters:
    ///   - roomId: ID of the room
    ///   - spaceId: ID of the space
    /// - Returns: `true` if the room with the given ID is an ancestor of the space with the given ID .`false` otherwise
    public func isRoom(withId roomId: String, descendantOf spaceId: String) -> Bool {
        return self.graph.descendantsPerRoomId[spaceId]?.contains(roomId) ?? false
    }
    
    /// Allows to know if the room is oprhnaed (e.g. has no ancestor)
    /// - Parameters:
    ///   - roomId: ID of the room
    /// - Returns: `true` if the room with the given ID is orphaned .`false` otherwise
    public func isOrphanedRoom(withId roomId: String) -> Bool {
        return self.graph.orphanedRoomIds.contains(roomId) || self.graph.orphanedDirectRoomIds.contains(roomId)
    }
    
    /// Handle a sync response
    /// - Parameters:
    ///   - syncResponse: The sync response object
    public func handleSyncResponse(_ syncResponse: MXSyncResponse) {
        guard self.needsUpdate || !(syncResponse.rooms?.join?.isEmpty ?? true) || !(syncResponse.rooms?.invite?.isEmpty ?? true) || !(syncResponse.rooms?.leave?.isEmpty ?? true) || !(syncResponse.toDevice?.events.isEmpty ?? true) else
        {
            return
        }
        
        self.buildGraph()
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
                let space: MXSpace = MXSpace(roomId: room.roomId, session:self.session)
                self.completionQueue.async {
                    completion(.success(space))
                }
            case .failure(let error):
                self.completionQueue.async {
                    completion(.failure(error))
                }
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
    /// - Returns: A MXSpace with the associated roomId or null if room doesn't exists or the room type is not space.
    public func getSpace(withId spaceId: String) -> MXSpace? {
        var space = self.spacesPerId[spaceId]
        if space == nil, let newSpace = self.session.room(withRoomId: spaceId)?.toSpace() {
            space = newSpace
            self.spacesPerId[spaceId] = newSpace
        }
        return space
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
                    
                    // Build room hierarchy and events
                    var childrenIdsPerChildRoomId: [String: [String]] = [:]
                    var parentIdsPerChildRoomId: [String:Set<String>] = [:]
                    var spaceChildEventsPerChildRoomId: [String:[String:Any]] = [:]
                    for event in spaceChildrenResponse.events ?? [] where event.type == kMXEventTypeStringSpaceChild && event.wireContent.count > 0 {
                        spaceChildEventsPerChildRoomId[event.stateKey] = event.wireContent

                        var parentIds = parentIdsPerChildRoomId[event.stateKey] ?? Set()
                        parentIds.insert(event.roomId)
                        parentIdsPerChildRoomId[event.stateKey] = parentIds

                        var childrenIds = childrenIdsPerChildRoomId[event.roomId] ?? []
                        childrenIds.append(event.stateKey)
                        childrenIdsPerChildRoomId[event.roomId] = childrenIds
                    }
                    
                    // Build the child summaries of the queried space
                    let childInfos = self.spaceChildInfos(from: spaceChildrenResponse, excludedSpaceId: spaceId, childrenIdsPerChildRoomId: childrenIdsPerChildRoomId, parentIdsPerChildRoomId: parentIdsPerChildRoomId, spaceChildEventsPerChildRoomId: spaceChildEventsPerChildRoomId)

                    let spaceChildrenSummary = MXSpaceChildrenSummary(spaceSummary: spaceSummary, childInfos: childInfos)

                    self.completionQueue.async {
                        completion(.success(spaceChildrenSummary))
                    }
                }
            case .failure(let error):
                self.completionQueue.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Space graph computation
    
    private class PrepareDataResult {
        var isPreparingData = true
        var spaces: [MXSpace] = []
        var spacesPerId: [String : MXSpace] = [:]
        var directRoomIdsPerMemberId: [String: [String]] = [:]
        var computingSpaces: Set<String> = Set()
        var computingDirectRooms: Set<String> = Set()
        var isComputing: Bool {
            return !self.computingSpaces.isEmpty || !self.computingDirectRooms.isEmpty
        }
    }
    
    /// Build the graph of rooms
    private func buildGraph() {
        guard !self.isGraphBuilding && self.graphUpdateEnabled else {
            MXLog.debug("[MXSpaceService] buildGraph: aborted: graph is building or disabled")
            self.needsUpdate = true
            return
        }
        
        self.isGraphBuilding = true
        self.needsUpdate = false
        
        let startDate = Date()
        MXLog.debug("[MXSpaceService] buildGraph: started")
        
        var directRoomIds = Set<String>()
        let roomIds: [String] = self.session.rooms.compactMap { room in
            if room.isDirect {
                directRoomIds.insert(room.roomId)
            }
            return room.roomId
        }
        
        let output = PrepareDataResult()
        MXLog.debug("[MXSpaceService] buildGraph: preparing data for \(roomIds.count) rooms")
        self.prepareData(with: roomIds, index: 0, output: output) { result in

            MXLog.debug("[MXSpaceService] buildGraph: data prepared in \(Date().timeIntervalSince(startDate))")
            
            self.computSpaceGraph(with: result, roomIds: roomIds, directRoomIds: directRoomIds) { graph in
                self.graph = graph
                
                MXLog.debug("[MXSpaceService] buildGraph: ended after \(Date().timeIntervalSince(startDate))s")
                
                self.isGraphBuilding = false
                self.isInitialised = true
                
                NotificationCenter.default.post(name: MXSpaceService.didBuildSpaceGraph, object: self)

                self.processingQueue.async {
                    let store = MXSpaceFileStore(userId: self.session.myUserId, deviceId: self.session.myDeviceId)
                    if !store.store(spaceGraphData: self.graph) {
                        MXLog.error("[MXSpaceService] buildGraph: failed to store space graph")
                    }

                    // TODO improve updateNotificationsCount and call the method to all spaces once subspaces will be supported
                    self.notificationCounter.computeNotificationCount()
                }
            }
        }
    }

    private func prepareData(with roomIds:[String], index: Int, output: PrepareDataResult, completion: @escaping (_ result: PrepareDataResult) -> Void) {
        self.processingQueue.async {
            guard index < roomIds.count else {
                self.completionQueue.async {
                    output.isPreparingData = false
                    if !output.isComputing {
                        completion(output)
                    }
                }
                return
            }
            
            var _room: MXRoom?
            var _space: MXSpace?
            var isRoomDirect = false
            var _directUserId: String?
            self.sdkProcessingQueue.sync {
                _room = self.session.room(withRoomId: roomIds[index])
                
                if let room = _room {
                    _space = self.spacesPerId[room.roomId] ?? room.toSpace()
                    isRoomDirect = room.isDirect
                    _directUserId = room.directUserId
                }
            }
            
            guard let room = _room else {
                self.prepareData(with: roomIds, index: index+1, output: output, completion: completion)
                return
            }
            
            if let space = _space {
                output.computingSpaces.insert(space.spaceId)
                space.readChildRoomsAndMembers {
                    output.computingSpaces.remove(space.spaceId)
                    if !output.isPreparingData && !output.isComputing {
                        completion(output)
                    }
                }
                output.spaces.append(space)
                output.spacesPerId[space.spaceId] = space

                self.prepareData(with: roomIds, index: index+1, output: output, completion: completion)
            } else if isRoomDirect {
                if let directUserId = _directUserId {
                    var rooms = output.directRoomIdsPerMemberId[directUserId] ?? []
                    rooms.append(room.roomId)
                    output.directRoomIdsPerMemberId[directUserId] = rooms
                    self.prepareData(with: roomIds, index: index+1, output: output, completion: completion)
                } else {
                    self.sdkProcessingQueue.async {
                        output.computingDirectRooms.insert(room.roomId)
                        
                        room.members { response in
                            guard let members = response.value as? MXRoomMembers else {
                                self.prepareData(with: roomIds, index: index+1, output: output, completion: completion)
                                return
                            }

                            let membersId = members.members?.compactMap({ roomMember in
                                return roomMember.userId != self.session.myUserId ? roomMember.userId : nil
                            }) ?? []

                            assert(membersId.count == 1)

                            self.processingQueue.async {
                                membersId.forEach { memberId in
                                    var rooms = output.directRoomIdsPerMemberId[memberId] ?? []
                                    rooms.append(room.roomId)
                                    output.directRoomIdsPerMemberId[memberId] = rooms
                                }
                                
                                output.computingDirectRooms.remove(room.roomId)
                                if !output.isPreparingData && !output.isComputing {
                                    completion(output)
                                }
                            }
                        }
                        
                        self.prepareData(with: roomIds, index: index+1, output: output, completion: completion)
                    }
                }
            } else {
                self.prepareData(with: roomIds, index: index+1, output: output, completion: completion)
            }
        }
    }
    
    private func computSpaceGraph(with result: PrepareDataResult, roomIds: [String], directRoomIds: Set<String>, completion: @escaping (_ graph: MXSpaceGraphData) -> Void) {
        let startDate = Date()
        MXLog.debug("[MXSpaceService] computSpaceGraph: started")
        
        self.processingQueue.async {
            var parentIdsPerRoomId: [String : Set<String>] = [:]
            result.spaces.forEach { space in
                space.updateChildSpaces(with: result.spacesPerId)
                space.updateChildDirectRooms(with: result.directRoomIdsPerMemberId)
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
            
            let rootSpaces = result.spaces.filter { space in
                return parentIdsPerRoomId[space.spaceId] == nil
            }
            
            var ancestorsPerRoomId: [String: Set<String>] = [:]
            var descendantsPerRoomId: [String: Set<String>] = [:]
            rootSpaces.forEach { space in
                self.buildRoomHierarchy(with: space, visitedSpaceIds: [], ancestorsPerRoomId: &ancestorsPerRoomId, descendantsPerRoomId: &descendantsPerRoomId)
            }
            
            var orphanedRoomIds: Set<String> = Set<String>()
            var orphanedDirectRoomIds: Set<String> = Set<String>()
            for roomId in roomIds {
                let isRoomDirect = directRoomIds.contains(roomId)
                if !isRoomDirect && parentIdsPerRoomId[roomId] == nil {
                    orphanedRoomIds.insert(roomId)
                } else if isRoomDirect && parentIdsPerRoomId[roomId] == nil {
                    orphanedDirectRoomIds.insert(roomId)
                }
            }

            let graph = MXSpaceGraphData(
                spaceRoomIds: result.spaces.map({ space in
                    space.spaceId
                }),
                parentIdsPerRoomId: parentIdsPerRoomId,
                ancestorsPerRoomId: ancestorsPerRoomId,
                descendantsPerRoomId: descendantsPerRoomId,
                rootSpaceIds: rootSpaces.map({ space in
                    space.spaceId
                }),
                orphanedRoomIds: orphanedRoomIds,
                orphanedDirectRoomIds: orphanedDirectRoomIds)
            
            MXLog.debug("[MXSpaceService] computSpaceGraph: space graph computed in \(Date().timeIntervalSince(startDate))s")

            self.completionQueue.async {
                completion(graph)
            }
        }
    }

    private func buildRoomHierarchy(with space: MXSpace, visitedSpaceIds: [String], ancestorsPerRoomId: inout [String: Set<String>], descendantsPerRoomId: inout [String: Set<String>]) {
        var visitedSpaceIds = visitedSpaceIds
        visitedSpaceIds.append(space.spaceId)
        space.childRoomIds.forEach { roomId in
            var parentIds = ancestorsPerRoomId[roomId] ?? Set<String>()
            visitedSpaceIds.forEach { spaceId in
                parentIds.insert(spaceId)
                
                var descendantIds = descendantsPerRoomId[spaceId] ?? Set<String>()
                descendantIds.insert(roomId)
                descendantsPerRoomId[spaceId] = descendantIds
            }
            ancestorsPerRoomId[roomId] = parentIds
        }
        space.childSpaces.forEach { childSpace in
            buildRoomHierarchy(with: childSpace, visitedSpaceIds: visitedSpaceIds, ancestorsPerRoomId: &ancestorsPerRoomId, descendantsPerRoomId: &descendantsPerRoomId)
        }
    }
    
    // MARK: - Notification handling
    
    private func registerNotificationObservers() {
        self.sessionStateDidChangeObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.mxSessionStateDidChange, object: session, queue: nil) { [weak self] notification in
            guard let session = self?.session, session.state == .storeDataReady else {
                return
            }
            
            self?.loadData()
        }
    }
    
    private func unregisterNotificationObservers() {
        if let observer = self.sessionStateDidChangeObserver {
            NotificationCenter.default.removeObserver(observer)
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
    
    private func spaceChildInfos(from spaceChildrenResponse: MXSpaceChildrenResponse, excludedSpaceId: String, childrenIdsPerChildRoomId: [String: [String]], parentIdsPerChildRoomId: [String:Set<String>], spaceChildEventsPerChildRoomId: [String:[String:Any]]) -> [MXSpaceChildInfo] {
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
                        
            return self.createSpaceChildInfo(with: spaceChildSummaryResponse, and: childStateEvent, parentIds: parentIdsPerChildRoomId[spaceId], childrenIds: childrenIdsPerChildRoomId[spaceId], childEvents: spaceChildEventsPerChildRoomId[spaceId])
        }
        
        return childInfos
    }
    
    private func createSpaceChildInfo(with spaceChildSummaryResponse: MXSpaceChildSummaryResponse, and spaceChildStateEvent: MXEvent?, parentIds: Set<String>?, childrenIds: [String]?, childEvents: [String:Any]?) -> MXSpaceChildInfo {
        
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
                         canonicalAlias: spaceChildSummaryResponse.canonicalAlias,
                         avatarUrl: spaceChildSummaryResponse.avatarUrl,
                         order: spaceChildContent?.order,
                         activeMemberCount: spaceChildSummaryResponse.numJoinedMembers,
                         autoJoin: childEvents?[kMXEventTypeStringAutoJoinKey] as? Bool ?? false,
                         suggested: childEvents?[kMXEventTypeStringSuggestedKey] as? Bool ?? false,
                         parentIds: parentIds ?? Set(),
                         childrenIds: childrenIds ?? [],
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
    ///   - success: A closure called when the operation is complete.
    ///   - failure: A closure called  when the operation fails.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    @objc public func getSpaceChildrenForSpace(withId spaceId: String, suggestedOnly: Bool, limit: Int, success: @escaping (MXSpaceChildrenSummary) -> Void, failure: @escaping (Error) -> Void) -> MXHTTPOperation {
        return self.getSpaceChildrenForSpace(withId: spaceId, suggestedOnly: suggestedOnly, limit: limit) { (response) in
            uncurryResponse(response, success: success, failure: failure)
        }
    }
}

// MARK: - Internal room additions
extension MXRoom {
    
    func toSpace() -> MXSpace? {
        guard let summary = self.summary, summary.roomType == .space else {
            return nil
        }
        return MXSpace(roomId: self.roomId, session: self.mxSession)
    }
}

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
    public static let didInitialise = Notification.Name("MXSpaceServiceDidInitialise")

    /// Posted once the graph of rooms is up and running
    public static let didBuildSpaceGraph = Notification.Name("MXSpaceServiceDidBuildSpaceGraph")
}

/// MXSpaceService enables to handle spaces.
@objcMembers
public class MXSpaceService: NSObject {

    // MARK: - Properties

    private let spacesPerIdReadWriteQueue: DispatchQueue

    private unowned let session: MXSession
    
    private lazy var stateEventBuilder: MXRoomInitialStateEventBuilder = {
        return MXRoomInitialStateEventBuilder()
    }()
    
    private let roomTypeMapper: MXRoomTypeMapper
    
    private let processingQueue: DispatchQueue
    private let sdkProcessingQueue: DispatchQueue
    private let completionQueue: DispatchQueue
    
    private var spacesPerId: [String: MXSpace] = [:]
    
    private var isGraphBuilding = false;
    private var isClosed = false;
    
    private var sessionStateDidChangeObserver: Any?

    private var graph: MXSpaceGraphData = MXSpaceGraphData() {
        didSet {
            var spacesPerId: [String:MXSpace] = [:]
            self.graph.spaceRoomIds.forEach { spaceId in
                if let space = self.getSpace(withId: spaceId) {
                    spacesPerId[spaceId] = space
                }
            }
            spacesPerIdReadWriteQueue.sync(flags: .barrier) {
                self.spacesPerId = spacesPerId
            }
        }
    }
    
    // MARK: Public

    /// The instance of `MXSpaceNotificationCounter` that computes the number of unread messages for each space
    public let notificationCounter: MXSpaceNotificationCounter
    
    /// List of `MXSpace` instances of the high level spaces.
    public var rootSpaces: [MXSpace] {
        return self.graph.rootSpaceIds.compactMap { spaceId in
            self.getSpace(withId: spaceId)
        }
    }
    
    /// List of `MXRoomSummary` of the high level spaces.
    public var rootSpaceSummaries: [MXRoomSummary] {
        return self.graph.rootSpaceIds.compactMap { spaceId in
            self.session.roomSummary(withRoomId: spaceId)
        }
    }
    
    /// List of `MXRoomSummary` of all spaces known by the user.
    public var spaceSummaries: [MXRoomSummary] {
        return self.graph.spaceRoomIds.compactMap { spaceId in
            self.session.roomSummary(withRoomId: spaceId)
        }
    }

    /// `true` if the `MXSpaceService` instance needs to be updated (e.g. the instance was busy while `handleSync` was called). `false` otherwise
    public private(set) var needsUpdate: Bool = true
    
    /// Set it to `false` if you want to temporarily disable graph update. This will be set automatically to `true` after next sync of the `MXSession`.
    public var graphUpdateEnabled = true
    
    /// List of ID of all the ancestors (direct parent spaces and parent spaces of the direct parent spaces) by room ID.
    public var ancestorsPerRoomId: [String:Set<String>] {
        return graph.ancestorsPerRoomId
    }
    
    /// The `MXSpaceService` instance is initialised if a previously saved graph has been restored or after the first sync.
    public private(set) var isInitialised = false {
        didSet {
            if !oldValue && isInitialised {
                self.completionQueue.async {
                    NotificationCenter.default.post(name: MXSpaceService.didInitialise, object: self)
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
        self.spacesPerIdReadWriteQueue = DispatchQueue(
          label: "org.matrix.sdk.MXSpaceService.spacesPerIdReadWriteQueue",
          attributes: .concurrent
        )

        super.init()
        
        self.registerNotificationObservers()
    }
    
    deinit {
        unregisterNotificationObservers()
    }
    
    // MARK: - Public
    
    /// close the service and free all data
    public func close() {
        self.isClosed = true
        self.graph = MXSpaceGraphData()
        self.notificationCounter.close()
        self.isInitialised = false
        self.completionQueue.async {
            NotificationCenter.default.post(name: MXSpaceService.didBuildSpaceGraph, object: self)
        }
    }
    
    /// Loads graph from the given store
    public func loadData() {
        self.processingQueue.async {
            var _myUserId: String?
            var _myDeviceId: String?
            
            self.sdkProcessingQueue.sync {
                _myUserId = self.session.myUserId
                _myDeviceId = self.session.myDeviceId
            }
            
            guard let myUserId = _myUserId, let myDeviceId = _myDeviceId else {
                MXLog.error("[MXSpaceService] loadData: Unexpectedly found nil for myUserId and/or myDeviceId")
                return
            }
            
            let store = MXSpaceFileStore(userId: myUserId, deviceId: myDeviceId)
            
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
    
    /// Returns the set of direct parent IDs of the given room
    /// - Parameters:
    ///   - roomId: ID of the room
    /// - Returns: set of direct parent IDs of the given room. Empty set if the room has no parent.
    public func directParentIds(ofRoomWithId roomId: String) -> Set<String> {
        return graph.parentIdsPerRoomId[roomId] ?? Set()
    }
    
    /// Returns the set of direct parent IDs of the given room for which the room is suggested or not according to the request.
    /// - Parameters:
    ///   - roomId: ID of the room
    ///   - suggested: If `true` the method will return the parent IDs where the room is suggested. If `false`  the method will return the parent IDs where the room is NOT suggested
    /// - Returns: set of direct parent IDs of the given room. Empty set if the room has no parent.
    public func directParentIds(ofRoomWithId roomId: String, whereRoomIsSuggested suggested: Bool) -> Set<String> {
        return directParentIds(ofRoomWithId: roomId).filter { spaceId in
            guard let space = spacesPerId[spaceId] else {
                return false
            }
            return (suggested && space.suggestedRoomIds.contains(roomId)) || (!suggested && !space.suggestedRoomIds.contains(roomId))
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
    
    /// Returns the first ancestor which is a root space
    /// - Parameters:
    ///   - roomId: ID of the room
    /// - Returns: Instance of the ancestor if found. `nil` otherwise
    public func firstRootAncestorForRoom(withId roomId: String) -> MXSpace? {
        if let ancestorIds = ancestorsPerRoomId[roomId] {
            for ancestorId in ancestorIds where ancestorsPerRoomId[ancestorId] == nil {
                return spacesPerId[ancestorId]
            }
        }
        
        return nil
    }
    
    /// Handle a sync response
    /// - Parameters:
    ///   - syncResponse: The sync response object
    public func handleSyncResponse(_ syncResponse: MXSyncResponse) {
         guard self.needsUpdate || !(syncResponse.rooms?.join?.isEmpty ?? true) || !(syncResponse.rooms?.invite?.isEmpty ?? true) || !(syncResponse.rooms?.leave?.isEmpty ?? true) || !(syncResponse.toDevice?.events.isEmpty ?? true) else {
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
    ///   - aliasLocalPart: local part of the alias
    ///   (e.g. for the alias "#my_alias:example.org", the local part is "my_alias")
    ///   - inviteArray: list of invited user IDs
    ///   - completion: A closure called when the operation completes.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func createSpace(withName name: String?, topic: String?, isPublic: Bool, aliasLocalPart: String? = nil, inviteArray: [String]? = nil, completion: @escaping (MXResponse<MXSpace>) -> Void) -> MXHTTPOperation {
        
        let parameters = MXSpaceCreationParameters()
        parameters.name = name
        parameters.topic = topic
        parameters.preset = isPublic ? kMXRoomPresetPublicChat : kMXRoomPresetPrivateChat
        parameters.visibility = isPublic ? kMXRoomDirectoryVisibilityPublic : kMXRoomDirectoryVisibilityPrivate
        parameters.inviteArray = inviteArray
        if isPublic {
            parameters.roomAlias = aliasLocalPart
            let guestAccessStateEvent = self.stateEventBuilder.buildGuestAccessEvent(withAccess: .canJoin)
            parameters.addOrUpdateInitialStateEvent(guestAccessStateEvent)
            let historyVisibilityStateEvent = self.stateEventBuilder.buildHistoryVisibilityEvent(withVisibility: .worldReadable)
            parameters.addOrUpdateInitialStateEvent(historyVisibilityStateEvent)
            parameters.powerLevelContentOverride?.invite = 0 // default
        } else {
            parameters.powerLevelContentOverride?.invite = 50 // moderator
        }

        return self.createSpace(with: parameters, completion: completion)
    }
    
    /// Get a space from a roomId.
    /// - Parameter spaceId: The id of the space.
    /// - Returns: A MXSpace with the associated roomId or null if room doesn't exists or the room type is not space.
    public func getSpace(withId spaceId: String) -> MXSpace? {
        var space: MXSpace?
        spacesPerIdReadWriteQueue.sync {
           space = self.spacesPerId[spaceId]
        }
        if space == nil, let newSpace = self.session.room(withRoomId: spaceId)?.toSpace() {
            space = newSpace
            spacesPerIdReadWriteQueue.sync(flags: .barrier) {
                self.spacesPerId[spaceId] = newSpace
            }
        }
        return space
    }
        
    /// Get the space children informations of a given space from the server.
    /// - Parameters:
    ///   - spaceId: The room id of the queried space.
    ///   - suggestedOnly: If `true`, return only child events and rooms where the `m.space.child` event has `suggested: true`.
    ///   - limit: Optional. A limit to the maximum number of children to return per space. `-1` for no limit
    ///   - maxDepth: Optional. The maximum depth in the tree (from the root room) to return. `-1` for no limit
    ///   - paginationToken: Optional. Pagination token given to retrieve the next set of rooms.
    ///   - completion: A closure called when the operation completes.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func getSpaceChildrenForSpace(withId spaceId: String,
                                         suggestedOnly: Bool,
                                         limit: Int?,
                                         maxDepth: Int?,
                                         paginationToken: String?,
                                         completion: @escaping (MXResponse<MXSpaceChildrenSummary>) -> Void) -> MXHTTPOperation {
        return self.session.matrixRestClient.getSpaceChildrenForSpace(withId: spaceId, suggestedOnly: suggestedOnly, limit: limit, maxDepth: maxDepth, paginationToken: paginationToken) { (response) in
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

                    // Build room hierarchy and events
                    var childrenIdsPerChildRoomId: [String: [String]] = [:]
                    var parentIdsPerChildRoomId: [String:Set<String>] = [:]
                    var spaceChildEventsPerChildRoomId: [String:[String:Any]] = [:]
                    for room in spaceChildrenResponse.rooms ?? [] {
                        for event in room.childrenState ?? [] where event.wireContent.count > 0 {
                            spaceChildEventsPerChildRoomId[event.stateKey] = event.wireContent

                            var parentIds = parentIdsPerChildRoomId[event.stateKey] ?? Set()
                            parentIds.insert(room.roomId)
                            parentIdsPerChildRoomId[event.stateKey] = parentIds

                            var childrenIds = childrenIdsPerChildRoomId[room.roomId] ?? []
                            childrenIds.append(event.stateKey)
                            childrenIdsPerChildRoomId[room.roomId] = childrenIds
                        }
                    }
                    
                    var spaceInfo: MXSpaceChildInfo?
                    if let rootSpaceChildSummaryResponse = rooms.first(where: { spaceResponse -> Bool in spaceResponse.roomId == spaceId}) {
                        spaceInfo = self.createSpaceChildInfo(with: rootSpaceChildSummaryResponse, childrenIds: childrenIdsPerChildRoomId[spaceId], childEvents: spaceChildEventsPerChildRoomId[spaceId])
                    }
                    
                    // Build the child summaries of the queried space
                    let childInfos = self.spaceChildInfos(from: spaceChildrenResponse, excludedSpaceId: spaceId, childrenIdsPerChildRoomId: childrenIdsPerChildRoomId, parentIdsPerChildRoomId: parentIdsPerChildRoomId, spaceChildEventsPerChildRoomId: spaceChildEventsPerChildRoomId)

                    let spaceChildrenSummary = MXSpaceChildrenSummary(spaceInfo: spaceInfo, childInfos: childInfos, nextBatch: spaceChildrenResponse.nextBatch)

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
        private var _spaces: [MXSpace] = []
        private var _spacesPerId: [String : MXSpace] = [:]
        private var _directRoomIdsPerMemberId: [String: [String]] = [:]
        private var computingSpaces: Set<String> = Set()
        private var computingDirectRooms: Set<String> = Set()
        
        var spaces: [MXSpace] {
            var result: [MXSpace] = []
            self.serialQueue.sync {
                result = self._spaces
            }
            return result
        }
        var spacesPerId: [String : MXSpace] {
            var result: [String : MXSpace] = [:]
            self.serialQueue.sync {
                result = self._spacesPerId
            }
            return result
        }
        var directRoomIdsPerMemberId: [String: [String]] {
            var result: [String: [String]] = [:]
            self.serialQueue.sync {
                result = self._directRoomIdsPerMemberId
            }
            return result
        }
        var isPreparingData = true
        var isComputing: Bool {
            var isComputing = false
            self.serialQueue.sync {
                isComputing = !self.computingSpaces.isEmpty || !self.computingDirectRooms.isEmpty
            }
            return isComputing
        }
        
        private let serialQueue = DispatchQueue(label: "org.matrix.sdk.MXSpaceService.PrepareDataResult.serialQueue")
        
        func add(space: MXSpace) {
            self.serialQueue.sync {
                self._spaces.append(space)
                self._spacesPerId[space.spaceId] = space
            }
        }
        
        func add(directRoom: MXRoom, toUserWithId userId: String) {
            self.serialQueue.sync {
                var rooms = self._directRoomIdsPerMemberId[userId] ?? []
                rooms.append(directRoom.roomId)
                self._directRoomIdsPerMemberId[userId] = rooms
            }
        }
        
        func setComputing(_ isComputing: Bool, forSpace space: MXSpace) {
            self.serialQueue.sync {
                if isComputing {
                    computingSpaces.insert(space.spaceId)
                } else {
                    computingSpaces.remove(space.spaceId)
                }
            }
        }
        
        func setComputing(_ isComputing: Bool, forDirectRoom room: MXRoom) {
            self.serialQueue.sync {
                if isComputing {
                    computingDirectRooms.insert(room.roomId)
                } else {
                    computingDirectRooms.remove(room.roomId)
                }
            }
        }
    }
    
    /// Build the graph of rooms
    private func buildGraph() {
        guard !self.isClosed && !self.isGraphBuilding && self.graphUpdateEnabled else {
            MXLog.debug("[MXSpaceService] buildGraph: aborted: graph is building or disabled")
            self.needsUpdate = true
            return
        }
        
        self.isGraphBuilding = true
        self.needsUpdate = false
        
        let startDate = Date()
        MXLog.debug("[MXSpaceService] buildGraph: started")
        
        var directRoomIds = Set(session.directRooms?.flatMap(\.value) ?? [])
        let roomIds = session.rooms.compactMap(\.roomId)
        
        let output = PrepareDataResult()
        MXLog.debug("[MXSpaceService] buildGraph: preparing data for \(roomIds.count) rooms")
        self.prepareData(with: roomIds, index: 0, output: output) { result in
            guard !self.isClosed else {
                return
            }
            
            MXLog.debug("[MXSpaceService] buildGraph: data prepared in \(Date().timeIntervalSince(startDate))")
            
            self.computSpaceGraph(with: result, roomIds: roomIds, directRoomIds: directRoomIds) { graph in
                guard !self.isClosed else {
                    return
                }
                
                self.graph = graph
                
                MXLog.debug("[MXSpaceService] buildGraph: ended after \(Date().timeIntervalSince(startDate))s")
                
                self.isGraphBuilding = false
                self.isInitialised = true
                
                NotificationCenter.default.post(name: MXSpaceService.didBuildSpaceGraph, object: self)

                self.processingQueue.async {
                    var _myUserId: String?
                    var _myDeviceId: String?
                    
                    self.sdkProcessingQueue.sync {
                        _myUserId = self.session.myUserId
                        _myDeviceId = self.session.myDeviceId
                    }
                    
                    guard let myUserId = _myUserId, let myDeviceId = _myDeviceId else {
                        MXLog.error("[MXSpaceService] buildGraph: Unexpectedly found nil for myUserId and/or myDeviceId")
                        return
                    }
                    
                    let store = MXSpaceFileStore(userId: myUserId, deviceId: myDeviceId)
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
        guard !self.isClosed else {
            // abort prepareData if the service is closed. No completion needed
            return
        }
        
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
            
            self.sdkProcessingQueue.async {
                guard let room = self.session.room(withRoomId: roomIds[index]) else {
                    self.prepareData(with: roomIds, index: index+1, output: output, completion: completion)
                    return
                }

                var space: MXSpace?
                self.spacesPerIdReadWriteQueue.sync {
                    space = self.spacesPerId[room.roomId] ?? room.toSpace()
                }
                
                self.prepareData(with: roomIds, index: index, output: output, room: room, space: space, isRoomDirect: room.isDirect, directUserId: room.directUserId, completion: completion)
            }
        }
    }
    
    private func prepareData(with roomIds:[String], index: Int, output: PrepareDataResult, room: MXRoom, space _space: MXSpace?, isRoomDirect:Bool, directUserId _directUserId: String?, completion: @escaping (_ result: PrepareDataResult) -> Void) {
        
        guard !self.isClosed else {
            // abort prepareData if the service is closed. No completion needed
            return
        }
        
        self.processingQueue.async {
            if let space = _space {
                output.setComputing(true, forSpace: space)
                space.readChildRoomsAndMembers {
                    output.setComputing(false, forSpace: space)
                    if !output.isPreparingData && !output.isComputing {
                        guard !self.isClosed else {
                            // abort prepareData if the service is closed. No completion needed
                            return
                        }
                        
                        completion(output)
                    }
                }
                output.add(space: space)

                self.prepareData(with: roomIds, index: index+1, output: output, completion: completion)
            } else if isRoomDirect {
                if let directUserId = _directUserId {
                    output.add(directRoom: room, toUserWithId: directUserId)
                    self.prepareData(with: roomIds, index: index+1, output: output, completion: completion)
                } else {
                    self.sdkProcessingQueue.async {
                        output.setComputing(true, forDirectRoom: room)
                        
                        room.members { response in
                            guard !self.isClosed else {
                                // abort prepareData if the service is closed. No completion needed
                                return
                            }
                            
                            guard let members = response.value as? MXRoomMembers else {
                                self.prepareData(with: roomIds, index: index+1, output: output, completion: completion)
                                return
                            }

                            let membersId = members.members?.compactMap({ roomMember in
                                return roomMember.userId != self.session.myUserId ? roomMember.userId : nil
                            }) ?? []

                            self.processingQueue.async {
                                membersId.forEach { memberId in
                                    output.add(directRoom: room, toUserWithId: memberId)
                                }
                                
                                output.setComputing(false, forDirectRoom: room)
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
        MXLog.debug("[MXSpaceService] computSpaceGraph: started for \(roomIds.count) rooms, \(directRoomIds.count) direct rooms, \(result.spaces.count) spaces, \(result.spaces.reduce(0, { $0 + $1.childSpaces.count })) child spaces, \(result.spaces.reduce(0, { $0 + $1.childRoomIds.count })) child rooms,  \(result.spaces.reduce(0, { $0 + $1.otherMembersId.count })) other members, \(result.directRoomIdsPerMemberId.count) members")
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
            }.sorted { space1, space2 in
                let _space1Order = space1.order
                let _space2Order = space2.order
                
                if let space1Order = _space1Order, let space2Order = _space2Order {
                    return space1Order <= space2Order
                }
                
                if _space1Order == nil && _space2Order == nil {
                    return space1.spaceId <= space2.spaceId
                } else if _space1Order != nil && _space2Order == nil {
                    return true
                } else {
                    return false
                }
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
        roomSummary.displayName = spaceChildSummaryResponse.name
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
            
            return self.createSpaceChildInfo(with: spaceChildSummaryResponse, childrenIds: childrenIdsPerChildRoomId[spaceId], childEvents: spaceChildEventsPerChildRoomId[spaceId])
        }
        
        return childInfos
    }
    
    private func createSpaceChildInfo(with spaceChildSummaryResponse: MXSpaceChildSummaryResponse, childrenIds: [String]?, childEvents: [String:Any]?) -> MXSpaceChildInfo {
        
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
                         activeMemberCount: spaceChildSummaryResponse.numJoinedMembers,
                         autoJoin: childEvents?[kMXEventTypeStringAutoJoinKey] as? Bool ?? false,
                         suggested: childEvents?[kMXEventTypeStringSuggestedKey] as? Bool ?? false,
                         childrenIds: childrenIds ?? [])
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
    ///   - aliasLocalPart: local part of the alias
    ///   (e.g. for the alias "#my_alias:example.org", the local part is "my_alias")
    ///   - inviteArray: list of invited user IDs
    ///   - success: A closure called when the operation is complete.
    ///   - failure: A closure called  when the operation fails.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    @objc public func createSpace(withName name: String, topic: String?, isPublic: Bool, aliasLocalPart: String?, inviteArray: [String]?, success: @escaping (MXSpace) -> Void, failure: @escaping (Error) -> Void) -> MXHTTPOperation {
        return self.createSpace(withName: name, topic: topic, isPublic: isPublic, aliasLocalPart: aliasLocalPart, inviteArray: inviteArray) { (response) in
            uncurryResponse(response, success: success, failure: failure)
        }
    }
    
    /// Get the space children informations of a given space from the server.
    /// - Parameters:
    ///   - spaceId: The room id of the queried space.
    ///   - suggestedOnly: If `true`, return only child events and rooms where the `m.space.child` event has `suggested: true`.
    ///   - limit: Optional. A limit to the maximum number of children to return per space. `-1` for no limit
    ///   - maxDepth: Optional. The maximum depth in the tree (from the root room) to return. `-1` for no limit
    ///   - paginationToken: Optional. Pagination token given to retrieve the next set of rooms.
    ///   - success: A closure called when the operation is complete.
    ///   - failure: A closure called  when the operation fails.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    @objc public func getSpaceChildrenForSpace(withId spaceId: String, suggestedOnly: Bool, limit: Int, maxDepth: Int, paginationToken: String?, success: @escaping (MXSpaceChildrenSummary) -> Void, failure: @escaping (Error) -> Void) -> MXHTTPOperation {
        return self.getSpaceChildrenForSpace(withId: spaceId, suggestedOnly: suggestedOnly, limit: limit, maxDepth: maxDepth, paginationToken: paginationToken) { (response) in
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

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

enum MXThreadEventTimelineError: Error {
    case initialEventNotFound
}

@objcMembers
public class MXThreadEventTimeline: NSObject, MXEventTimeline {
    
    public var timelineId: String
    
    public var initialEventId: String?
    
    public var isLiveTimeline: Bool = false
    
    public var roomEventFilter: MXRoomEventFilter?
    
    public var state: MXRoomState?  // not used
    
    private var listeners: [MXEventListener] = []
    
    /// The store to get events from
    private var store: MXStore
    
    /// The thread
    private var thread: MXThread
    
    /// The events enumerator to paginate messages from the store.
    private var storeMessagesEnumerator: MXEventsEnumerator?
    
    /// Backward pagination token for thread timelines is managed locally.
    private var backwardsPaginationToken: String?
    
    /// Forward pagination token for thread timelines is managed locally.
    private var forwardsPaginationToken: String?
    
    private var hasReachedHomeServerBackwardsPaginationEnd: Bool = false
    private var hasReachedHomeServerForwardsPaginationEnd: Bool = false
    
    /// The current pending request
    private var currentHttpOperation: MXHTTPOperation?
    private let lockListeners = NSRecursiveLock()
    
    private lazy var threadEventFilter: MXRoomEventFilter = {
        let filter = MXRoomEventFilter()
        filter.relatedByTypes = [MXEventRelationTypeThread]
        return filter
    }()
    
    public required convenience init(thread: MXThread, andInitialEventId initialEventId: String?) {
        guard let session = thread.session else {
            fatalError("[MXThreadEventTimeline] Initializer: Session must be provided")
        }
        let store: MXStore
        if initialEventId != nil {
            store = MXMemoryStore()
            store.open(with: session.credentials, onComplete: nil, failure: nil)
        } else {
            store = session.store
        }
        self.init(thread: thread, initialEventId: initialEventId, andStore: store)
    }
    
    public required init(thread: MXThread, initialEventId: String?, andStore store: MXStore) {
        self.timelineId = UUID().uuidString
        self.thread = thread
        self.initialEventId = initialEventId
        if initialEventId == nil {
            self.isLiveTimeline = true
        } else {
            hasReachedHomeServerBackwardsPaginationEnd = true
            hasReachedHomeServerForwardsPaginationEnd = true
        }
        self.store = store
        self.thread = thread
        self.state = MXRoomState(roomId: thread.roomId, andMatrixSession: thread.session, andDirection: true)
        super.init()
        self.roomEventFilter = threadEventFilter
    }
    
    public func initialiseState(_ stateEvents: [MXEvent]) {
        state?.handleStateEvents(stateEvents)
    }
    
    public func destroy() {
        removeAllListeners()
        
        currentHttpOperation?.cancel()
        currentHttpOperation = nil
        
        if !isLiveTimeline && !store.isPermanent {
            // Release past timeline events stored in memory
            store.deleteAllData()
        }
    }
    
    public func canPaginate(_ direction: MXTimelineDirection) -> Bool {
        switch direction {
        case .backwards:
            // canPaginate depends on two things:
            //  - did we end to paginate from the MXStore?
            //  - did we reach the top of the pagination in our requests to the home server?
            return storeMessagesEnumerator?.remaining ?? 0 > 0 || !hasReachedHomeServerBackwardsPaginationEnd
        case .forwards:
            if isLiveTimeline {
                // Matrix is not yet able to guess the future
                return false
            } else {
                return !hasReachedHomeServerForwardsPaginationEnd
            }
        @unknown default:
            fatalError("[MXThreadEventTimeline][\(timelineId)] canPaginate: Unknown direction")
        }
    }
    
    public func resetPagination() {
        // Reset store pagination
        storeMessagesEnumerator = store.messagesEnumerator(forRoom: thread.roomId)

        if isLiveTimeline {
            hasReachedHomeServerBackwardsPaginationEnd = false
            hasReachedHomeServerForwardsPaginationEnd = false
        }
    }
    
    public func __resetPaginationAroundInitialEvent(withLimit limit: UInt,
                                                    success: @escaping () -> Void,
                                                    failure: @escaping (Error) -> Void) -> MXHTTPOperation {
        guard let initialEventId = initialEventId else {
            fatalError("[MXThreadEventTimeline][\(timelineId)] resetPaginationAroundInitialEventWithLimit cannot be called on live timeline")
        }
        
        // Reset the store
        if !store.isPermanent {
            store.deleteAllData()
        }
        
        backwardsPaginationToken = nil
        forwardsPaginationToken = nil
        hasReachedHomeServerBackwardsPaginationEnd = false
        hasReachedHomeServerForwardsPaginationEnd = false
        
        guard thread.session != nil else {
            return MXHTTPOperation()
        }

        //  We cannot use /context api here, like in a room timeline.
        //  This is due to https://github.com/vector-im/element-meta/issues/150
        //  So we're paginating with /relations api until we find the specified event.
        //  Can be replaced by the old /context implementation when we have the fix in backend.

        var eventFound: Bool = false
        var paginationError: Error? = nil
        let dispatchGroup = DispatchGroup()
        var paginationBlock: () -> Void = {}
        let result = MXHTTPOperation()

        paginationBlock = {
            dispatchGroup.enter()
            let newRequest = self.paginate(limit, direction: .backwards, onlyFromStore: false) { response in
                switch response {
                case .success:
                    if self.store.eventExists(withEventId: initialEventId, inRoom: self.thread.roomId) {
                        eventFound = true
                    } else if self.canPaginate(.backwards) {
                        paginationBlock()
                    } else {
                        paginationError = MXThreadEventTimelineError.initialEventNotFound
                    }
                case .failure(let error):
                    paginationError = error
                }
                dispatchGroup.leave()
            }
            result.mutate(to: newRequest)
        }

        paginationBlock()

        dispatchGroup.notify(queue: .main) {
            if eventFound {
                success()
            } else if let paginationError = paginationError {
                MXLog.error("[MXThreadEventTimeline] resetPaginationAroundInitialEvent failed", context: [
                    "error": paginationError,
                    "timeline_id": self.timelineId
                ])
                failure(paginationError)
            } else {
                failure(MXThreadEventTimelineError.initialEventNotFound)
            }
        }

        return result
    }
    
    public func __paginate(_ numItems: UInt, direction: MXTimelineDirection, onlyFromStore: Bool, complete: @escaping () -> Void, failure: @escaping (Error) -> Void) -> MXHTTPOperation {
        assert(!(isLiveTimeline && direction == .forwards), "[MXThreadEventTimeline][\(timelineId)] Cannot paginate forwards on a live timeline")
        
        let operation = MXHTTPOperation()
        
        paginateFromStore(numberOfItems: numItems, direction: direction) { [weak self] eventsFromStore in
            guard let self = self else { return }
            
            var remainingNumItems = Int(numItems)
            let eventsFromStoreCount = eventsFromStore.count
            
            if direction == .backwards {
                // messagesFromStore are in chronological order
                // Handle events from the most recent
                for event in eventsFromStore.reversed() {
                    self.addEvent(event, direction: .backwards, fromStore: true)
                }
                
                remainingNumItems -= eventsFromStoreCount
                
                if onlyFromStore && eventsFromStoreCount > 0 {
                    DispatchQueue.main.async {
                        // Nothing more to do
                        MXLog.debug("[MXThreadEventTimeline][\(self.timelineId)] paginate: is done from the store")
                        complete()
                    }
                    return
                }
                
                if remainingNumItems <= 0 || self.hasReachedHomeServerBackwardsPaginationEnd {
                    DispatchQueue.main.async {
                        // Nothing more to do
                        MXLog.debug("[MXThreadEventTimeline][\(self.timelineId)] paginate: is done from the store")
                        complete()
                    }
                    return
                }
            }
            
            // Do not try to paginate forward if end has been reached
            if direction == .forwards && self.hasReachedHomeServerForwardsPaginationEnd {
                DispatchQueue.main.async {
                    // Nothing more to do
                    MXLog.debug("[MXThreadEventTimeline][\(self.timelineId)] paginate: is done")
                    complete()
                }
                return
            }
            
            // Not enough messages: make a pagination request to the home server from last known token
            MXLog.debug("[MXThreadEventTimeline][\(self.timelineId)] paginate: request \(remainingNumItems) messages from the server")
            
            var paginationToken: String?
            switch direction {
            case .backwards:
                paginationToken = self.backwardsPaginationToken
            case .forwards:
                paginationToken = self.forwardsPaginationToken
            @unknown default:
                fatalError("[MXThreadEventTimeline][\(self.timelineId)] paginate: unknown direction")
            }
            if let matrixRestClient = self.thread.session?.matrixRestClient {
                let operation2 = matrixRestClient.relations(forEvent: self.thread.id,
                                                            inRoom: self.thread.roomId,
                                                            relationType: MXEventRelationTypeThread,
                                                            eventType: nil,
                                                            from: paginationToken,
                                                            direction: direction,
                                                            limit: UInt(remainingNumItems),
                                                            completion: { [weak self] response in
                                                                guard let self = self else { return }
                                                                switch response {
                                                                case .success(let paginationResponse):
                                                                    self.processPaginationResponse(paginationResponse,
                                                                                                   direction: direction)
                                                                    complete()
                                                                case .failure(let error):
                                                                    failure(error)
                                                                }
                                                            })
                operation.mutate(to: operation2)
            }
        }
        
        return operation
    }
    
    public func remainingMessagesForBackPaginationInStore() -> UInt {
        return 0
    }
    
    public func handleJoinedRoomSync(_ roomSync: MXRoomSync, onComplete: @escaping () -> Void) {
        let events = roomSync.timeline.events
        fixRoomId(inEvents: events)
        let dispatchGroup = DispatchGroup()

        if let session = thread.session {
            dispatchGroup.enter()
            session.decryptEvents(events, inTimeline: nil) { _ in
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            events.forEach {
                self.notifyListeners($0, direction: .forwards)
            }
        }
    }
    
    public func handle(_ invitedRoomSync: MXInvitedRoomSync, onComplete: @escaping () -> Void) {
        //  no-op
    }
    
    public func handleLazyLoadedStateEvents(_ stateEvents: [MXEvent]) {
        //  no-op
    }
    
    public func __listen(toEvents onEvent: @escaping MXOnRoomEvent) -> MXEventListener {
        return __listen(toEventsOfTypes: nil, onEvent: onEvent)
    }
    
    public func __listen(toEventsOfTypes types: [String]?, onEvent: @escaping MXOnRoomEvent) -> MXEventListener {
        let listener = MXEventListener(sender: self, andEventTypes: types) { event, direction, any in
            onEvent(event, direction, any as? MXRoomState)
        }
        synchronizeListeners {
            self.listeners.append(listener)
        }
        return listener
    }
    
    public func remove(_ listener: MXEventListener) {
        synchronizeListeners {
            self.listeners.removeAll(where: { $0 === listener })
        }
    }
    
    public func removeAllListeners() {
        synchronizeListeners {
            self.listeners.removeAll()
        }
    }
    
    public func notifyListeners(_ event: MXEvent, direction: MXTimelineDirection) {
        var tmpListeners: [MXEventListener] = []
        synchronizeListeners {
            tmpListeners = self.listeners.map { $0.copy() as! MXEventListener }
        }
        for listener in tmpListeners {
            listener.notify(event, direction: direction, andCustomObject: state)
        }
    }
    
    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = MXThreadEventTimeline(thread: thread, initialEventId: initialEventId, andStore: store)
        
        copy.roomEventFilter = roomEventFilter
        
        // There can be only a single live timeline
        copy.isLiveTimeline = false
        
        return copy
    }
    
    //  MARK: - Private
    
    private func processPaginationResponse(_ response: MXAggregationPaginatedResponse, direction: MXTimelineDirection) {
        MXLog.debug("[MXThreadEventTimeline][\(self.timelineId)] processPaginationResponse: \(response.chunk.count) messages from the server, direction: \(direction)")

        decryptEvents(response.chunk) {
            //  process chunk first
            for event in response.chunk {
                self.addEvent(event, direction: direction, fromStore: false)
            }

            let updatePaginationInfo = {
                switch direction {
                case .backwards:
                    self.backwardsPaginationToken = response.nextBatch
                    self.hasReachedHomeServerBackwardsPaginationEnd = response.nextBatch == nil
                    MXLog.debug("[MXThreadEventTimeline][\(self.timelineId)] processPaginationResponse: hasReachedHomeServerBackwardsPaginationEnd: \(self.hasReachedHomeServerBackwardsPaginationEnd)")
                case .forwards:
                    self.forwardsPaginationToken = response.nextBatch
                    self.hasReachedHomeServerForwardsPaginationEnd = response.nextBatch == nil
                    MXLog.debug("[MXThreadEventTimeline][\(self.timelineId)] processPaginationResponse: hasReachedHomeServerForwardsPaginationEnd: \(self.hasReachedHomeServerForwardsPaginationEnd)")
                @unknown default:
                    fatalError("[MXThreadEventTimeline][\(self.timelineId)] processPaginationResponse: Unknown direction")
                }
            }

            //  then process the root if there is no more messages in server

            if let rootEvent = response.originalEvent, response.nextBatch == nil {
                self.decryptEvents([rootEvent]) {
                    self.addEvent(rootEvent, direction: direction, fromStore: false)
                    updatePaginationInfo()
                }
            } else {
                updatePaginationInfo()
            }
        }
    }
    
    private func paginateFromStore(numberOfItems: UInt, direction: MXTimelineDirection, completion: @escaping ([MXEvent]) -> Void) {
        switch direction {
        case .backwards:
            // For back pagination, try to get messages from the store first
            guard let storeMessagesEnumerator = storeMessagesEnumerator else {
                completion([])
                return
            }
            if let events = storeMessagesEnumerator.nextEventsBatch(numberOfItems, threadId: thread.id) {
                MXLog.debug("[MXThreadEventTimeline][\(timelineId)] paginateFromStore: \(numberOfItems) requested, \(events.count) fetched for thread: \(thread.id)")
                
                decryptEvents(events) {
                    completion(events)
                }
            } else {
                completion([])
            }
        case .forwards:
            completion([])
        @unknown default:
            fatalError("[MXThreadEventTimeline][\(timelineId)] paginateFromStore: Unknown direction")
        }
    }
    
    private func addEvent(_ event: MXEvent, direction: MXTimelineDirection, fromStore: Bool) {
        if fromStore {
            notifyListeners(event, direction: direction)
        } else {
            self.notifyListeners(event, direction: direction)
            thread.session?.threadingService.handleEvent(event, direction: direction, completion: nil)
            
            if !isLiveTimeline {
                store.storeEvent(forRoom: thread.roomId, event: event, direction: direction)
            }
        }
    }
    
    private func decryptEvents(_ events: [MXEvent], newerThanTimestamp timestamp: UInt64 = 0, completion: @escaping () -> Void) {
        let eventsToDecrypt: [MXEvent] = events.filter { $0.eventType == .roomEncrypted && $0.originServerTs > timestamp }
        
        if eventsToDecrypt.isEmpty {
            completion()
            return
        }
        
        if let session = thread.session {
            session.decryptEvents(eventsToDecrypt, inTimeline: timelineId, onComplete: { failedEvents in
                completion()
            })
        } else {
            completion()
        }
    }
    
    /// Thread safe access to listeners array
    private func synchronizeListeners(_ block: () -> Void) {
        lockListeners.lock()
        defer { lockListeners.unlock() }
        block()
    }
    
    private func fixRoomId(inEvents events: [MXEvent]) {
        for event in events {
            event.roomId = thread.roomId
        }
    }
}

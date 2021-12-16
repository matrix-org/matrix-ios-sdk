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
    private var hasReachedHomeServerForwardsPaginationEnd: Bool = false
    
    /// The current pending request
    private var currentHttpOperation: MXHTTPOperation?
    
    private lazy var threadEventFilter: MXRoomEventFilter = {
        let filter = MXRoomEventFilter()
        filter.relationTypes = [MXEventRelationTypeThread]
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
        }
        self.store = store
        self.thread = thread
        super.init()
        self.roomEventFilter = threadEventFilter
    }
    
    public func initialiseState(_ stateEvents: [MXEvent]) {
        //  no-op
    }
    
    public func destroy() {
        thread.session?.resetReplayAttackCheck(inTimeline: timelineId)
        
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
            return storeMessagesEnumerator?.remaining ?? 0 > 0 || !hasReachedHomeServerForwardsPaginationEnd
        case .forwards:
            if isLiveTimeline {
                // Matrix is not yet able to guess the future
                return false
            } else {
                return !hasReachedHomeServerForwardsPaginationEnd
            }
        @unknown default:
            fatalError("Unknown direction")
        }
    }
    
    public func resetPagination() {
        thread.session?.resetReplayAttackCheck(inTimeline: timelineId)
        
        // Reset store pagination
        storeMessagesEnumerator = store.messagesEnumerator(forRoom: thread.roomId)
    }
    
    public func __resetPaginationAroundInitialEvent(withLimit limit: UInt,
                                                    success: @escaping () -> Void,
                                                    failure: @escaping (Error) -> Void) -> MXHTTPOperation {
        guard let initialEventId = initialEventId else {
            fatalError("[MXThreadEventTimeline] resetPaginationAroundInitialEventWithLimit cannot be called on live timeline")
        }
        
        thread.session?.resetReplayAttackCheck(inTimeline: timelineId)
        
        // Reset the store
        if !store.isPermanent {
            store.deleteAllData()
        }
        
        backwardsPaginationToken = nil
        forwardsPaginationToken = nil
        hasReachedHomeServerForwardsPaginationEnd = false
        
        guard let session = thread.session else {
            return MXHTTPOperation()
        }
        
        return session.matrixRestClient.context(ofEvent: initialEventId,
                                                inRoom: thread.roomId,
                                                limit: limit,
                                                filter: threadEventFilter) { [weak self] response in
            guard let self = self else { return }
            switch response {
            case .success(let context):
                // Reset pagination state from here
                self.resetPagination()
                
                var events: [MXEvent] = []
                events.append(context.event)
                events.append(contentsOf: context.eventsBefore)
                events.append(contentsOf: context.eventsAfter)
                
                self.decryptEvents(events) {
                    self.addEvent(context.event, direction: .forwards, fromStore: false)
                    
                    for event in context.eventsBefore {
                        self.addEvent(event, direction: .backwards, fromStore: false)
                    }
                    
                    for event in context.eventsAfter {
                        self.addEvent(event, direction: .forwards, fromStore: false)
                    }
                    
                    self.backwardsPaginationToken = context.start
                    self.forwardsPaginationToken = context.end
                    
                    success()
                }
            case .failure(let error):
                MXLog.error("[MXThreadEventTimeline] resetPaginationAroundInitialEvent failed: \(error)")
                failure(error)
            }
        }
    }
    
    public func __paginate(_ numItems: UInt, direction: MXTimelineDirection, onlyFromStore: Bool, complete: @escaping () -> Void, failure: @escaping (Error) -> Void) -> MXHTTPOperation {
        assert(!(isLiveTimeline && direction == .forwards), "[MXThreadEventTimeline] Cannot paginate forwards on a live timeline")
        
        return MXHTTPOperation()
    }
    
    public func remainingMessagesForBackPaginationInStore() -> UInt {
        return 0
    }
    
    public func handleJoinedRoomSync(_ roomSync: MXRoomSync, onComplete: @escaping () -> Void) {
        
    }
    
    public func handle(_ invitedRoomSync: MXInvitedRoomSync, onComplete: @escaping () -> Void) {
        
    }
    
    public func handleLazyLoadedStateEvents(_ stateEvents: [MXEvent]) {
        
    }
    
    public func __listen(toEvents onEvent: @escaping MXOnRoomEvent) -> MXEventListener {
        return __listen(toEventsOfTypes: nil, onEvent: onEvent)
    }
    
    public func __listen(toEventsOfTypes types: [String]?, onEvent: @escaping MXOnRoomEvent) -> MXEventListener {
        let listener = MXEventListener(sender: self, andEventTypes: types) { event, direction, any in
            onEvent(event, direction, nil)
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
            listener.notify(event, direction: direction, andCustomObject: nil)
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
    
    private func paginateFromStore(numberOfItems: UInt, direction: MXTimelineDirection, completion: @escaping ([MXEvent]) -> Void) {
        switch direction {
        case .backwards:
            // For back pagination, try to get messages from the store first
            guard let storeMessagesEnumerator = storeMessagesEnumerator else {
                completion([])
                return
            }
            if let events = storeMessagesEnumerator.nextEventsBatch(numberOfItems, threadId: "") {
                MXLog.debug("[MXThreadEventTimeline][\(timelineId)] paginateFromStore: \(numberOfItems) requested, \(events.count) fetched for thread: ")
                
                decryptEvents(events) {
                    completion(events)
                }
            }
        case .forwards:
            completion([])
        @unknown default:
            fatalError("[MXThreadEventTimeline][\(timelineId)] paginateFromStore: Unknown direction")
        }
    }
    
    private func addEvent(_ event: MXEvent, direction: MXTimelineDirection, fromStore: Bool) {
        notifyListeners(event, direction: direction)
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
        objc_sync_enter(listeners)
        block()
        objc_sync_exit(listeners)
    }
    
    private func fixRoomId(inEvents events: [MXEvent]) {
        for event in events {
            event.roomId = thread.roomId
        }
    }
}

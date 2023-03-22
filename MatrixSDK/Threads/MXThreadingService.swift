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

/// MXThreadingService error
public enum MXThreadingServiceError: Int, Error {
    case sessionNotFound
    case unknown
}

/// MXThreadingService allThreads response
public struct MXThreadingServiceResponse {
    public let threads: [MXThreadProtocol]
    public let nextBatch: String?
}

// MARK: - MXThreadingService errors
extension MXThreadingServiceError: CustomNSError {
    public static let errorDomain = "org.matrix.sdk.threadingservice"

    public var errorCode: Int {
        return rawValue
    }

    public var errorUserInfo: [String: Any] {
        return [:]
    }
}

@objc
public protocol MXThreadingServiceDelegate: AnyObject {
    /// Delegate method to be called when thread are updated in any way.
    @objc optional func threadingServiceDidUpdateThreads(_ service: MXThreadingService)

    /// Delegate method to be called when a new local thread is created
    @objc optional func threadingService(_ service: MXThreadingService,
                                         didCreateNewThread thread: MXThread,
                                         direction: MXTimelineDirection)
}

@objcMembers
/// Threading service class.
public class MXThreadingService: NSObject {
    
    private weak var session: MXSession?
    
    private let lockThreads = NSRecursiveLock()
    private var threads: [String: MXThread] = [:]
    private let multicastDelegate: MXMulticastDelegate<MXThreadingServiceDelegate> = MXMulticastDelegate()

    /// Initializer
    /// - Parameter session: session instance
    public init(withSession session: MXSession) {
        self.session = session
        super.init()
    }

    /// Handle joined room sync
    /// - Parameter roomSync: room sync instance
    public func handleJoinedRoomSync(_ roomSync: MXRoomSync, forRoom roomId: String) {
        guard let session = session else {
            //  session closed
            return
        }

        let events = roomSync.timeline.events
        // Make sure that all events have a room id. They are skipped in some server responses
        events.forEach({ $0.roomId = roomId })
        session.decryptEvents(events, inTimeline: nil) { _ in
            let dispatchGroup = DispatchGroup()

            for event in events {
                dispatchGroup.enter()
                self.handleEvent(event, direction: .forwards) { _ in
                    dispatchGroup.leave()
                }
            }

            dispatchGroup.notify(queue: .main) {
                self.threads.values.filter { $0.roomId == roomId }.forEach { $0.handleJoinedRoomSync(roomSync) }
            }
        }
    }

    /// Adds event to the related thread instance
    /// - Parameters:
    ///   - event: event to be handled
    ///   - direction: direction of the event
    ///   - completion: Completion block containing the flag indicating that the event is handled
    public func handleEvent(_ event: MXEvent, direction: MXTimelineDirection, completion: ((Bool) -> Void)?) {
        guard MXSDKOptions.sharedInstance().enableThreads else {
            //  threads disabled in the SDK
            completion?(false)
            return
        }
        guard let session = session else {
            //  session closed
            completion?(false)
            return
        }
        if event.isInThread() {
            //  event is in a thread
            handleInThreadEvent(event, direction: direction, session: session, completion: completion)
        } else if let thread = thread(withId: event.eventId) {
            //  event is a thread root
            if thread.addEvent(event, direction: direction) {
                notifyDidUpdateThreads()
                completion?(true)
            } else {
                completion?(false)
            }
        } else if event.isEdit() {
            handleEditEvent(event, direction: direction, session: session, completion: completion)
        } else if event.eventType == .roomRedaction {
            handleRedactionEvent(event, direction: direction, session: session, completion: completion)
        } else {
            completion?(false)
        }
    }
    
    /// Get notifications count of threads in a room
    /// - Parameter roomId: Room identifier
    /// - Returns: Notifications count
    public func notificationsCount(forRoom roomId: String) -> MXThreadNotificationsCount {
        var notified: UInt = 0
        var highlighted: UInt = 0
        var notificationsNumber: UInt = 0
        for thread in unsortedThreads(inRoom: roomId) {
            notified += thread.notificationCount > 0 ? 1 : 0
            highlighted += thread.highlightCount > 0 ? 1 : 0
            notificationsNumber += thread.notificationCount
        }
        return MXThreadNotificationsCount(numberOfNotifiedThreads: notified,
                                          numberOfHighlightedThreads: highlighted,
                                          notificationsNumber: notificationsNumber)
    }
    
    /// Method to check an event is a thread root or not
    /// - Parameter event: event to be checked
    /// - Returns: true is given event is a thread root
    public func isEventThreadRoot(_ event: MXEvent) -> Bool {
        return thread(withId: event.eventId) != nil
    }
    
    /// Method to get a thread with specific identifier
    /// - Parameter identifier: identifier of a thread
    /// - Returns: thread instance if found, nil otherwise
    public func thread(withId identifier: String) -> MXThread? {
        lockThreads.lock()
        defer { lockThreads.unlock() }
        return threads[identifier]
    }
    
    public func createTempThread(withId identifier: String, roomId: String) -> MXThread {
        guard let session = session else {
            fatalError("Session must be available")
        }
        return MXThread(withSession: session, identifier: identifier, roomId: roomId)
    }
    
    /// Mark a thread as read
    /// - Parameter threadId: Thread id
    public func markThreadAsRead(_ threadId: String) {
        guard let thread = thread(withId: threadId) else {
            return
        }
        thread.markAsRead()
        notifyDidUpdateThreads()
    }
    
    @discardableResult
    public func allThreads(inRoomWithId roomId: String,
                           onlyParticipated: Bool,
                           completion: @escaping ([MXThreadProtocol]) -> Void) -> MXHTTPOperation? {
        return allThreads(inRoom: roomId, onlyParticipated: onlyParticipated) { response in
            switch response {
            case .success(let threads):
                completion(threads)
            case .failure(let error):
                MXLog.warning("[MXThreadingService] allThreads failed with error: \(error)")
                completion([])
            }
        }
    }
    
    @discardableResult
    public func allThreads(inRoom roomId: String,
                           from: String?,
                           onlyParticipated: Bool,
                           completion: @escaping (MXResponse<MXThreadingServiceResponse>) -> Void) -> MXHTTPOperation? {
        guard let session = session else {
            DispatchQueue.main.async {
                completion(.failure(MXThreadingServiceError.sessionNotFound))
            }
            return nil
        }

        var serverSupportThreads = false
        let dispatchGroup = DispatchGroup()

        dispatchGroup.enter()
        let operation = session.supportedMatrixVersions { response in
            switch response {
            case .success(let versions):
                serverSupportThreads = versions.supportsThreads
            default:
                break
            }
            dispatchGroup.leave()
        }

        dispatchGroup.notify(queue: .main) {
            if serverSupportThreads {
                let newOperation = session.matrixRestClient.threadsInRoomWithId(roomId, include: onlyParticipated ? .participated : .all, from: from) { response in
                    switch response {
                    case .success(let paginationResponse):
                        let rootEvents = paginationResponse.chunk

                        session.decryptEvents(rootEvents, inTimeline: nil) { _ in
                            let threads = rootEvents.map { self.thread(forRootEvent: $0, session: session) }.sorted(by: <)
                            let decryptionGroup = DispatchGroup()
                            for thread in threads {
                                guard let rootEvent = rootEvents.first(where: { $0.eventId == thread.id }) else {
                                    continue
                                }
                                if let rootEventEdition = session.store?.relations(forEvent: rootEvent.eventId,
                                                                                   inRoom: rootEvent.roomId,
                                                                                   relationType: MXEventRelationTypeReplace).sorted(by: >).last,
                                   let editedRootEvent = rootEvent.editedEvent(fromReplacementEvent: rootEventEdition) {
                                    decryptionGroup.enter()
                                    session.decryptEvents([editedRootEvent], inTimeline: nil) { _ in
                                        thread.updateRootMessage(editedRootEvent)
                                        decryptionGroup.leave()
                                    }
                                }
                                if let latestEvent = rootEvent.unsignedData.relations?.thread?.latestEvent {
                                    decryptionGroup.enter()
                                    session.decryptEvents([latestEvent], inTimeline: nil) { _ in
                                        thread.updateLastMessage(latestEvent)
                                        decryptionGroup.leave()
                                        if let edition = session.store?.relations(forEvent: latestEvent.eventId,
                                                                                  inRoom: latestEvent.roomId,
                                                                                  relationType: MXEventRelationTypeReplace).sorted(by: >).last,
                                           let editedLatestEvent = latestEvent.editedEvent(fromReplacementEvent: edition) {
                                            decryptionGroup.enter()
                                            session.decryptEvents([editedLatestEvent], inTimeline: nil) { _ in
                                                thread.updateLastMessage(editedLatestEvent)
                                                decryptionGroup.leave()
                                            }
                                        }
                                    }
                                }
                            }

                            decryptionGroup.notify(queue: .main) {
                                completion(.success(MXThreadingServiceResponse(threads: threads, nextBatch: paginationResponse.nextBatch)))
                            }
                        }

                    case .failure(let error):
                        completion(.failure(error))
                    }
                }

                operation.mutate(to: newOperation)
            } else {
                //  use local implementation
                if onlyParticipated {
                    completion(.success(MXThreadingServiceResponse(threads: self.localParticipatedThreads(inRoom: roomId), nextBatch: nil)))
                } else {
                    completion(.success(MXThreadingServiceResponse(threads: self.localThreads(inRoom: roomId), nextBatch: nil)))
                }
            }
        }

        return operation
    }

    @discardableResult
    public func allThreads(inRoom roomId: String,
                           onlyParticipated: Bool = false,
                           completion: @escaping (MXResponse<[MXThreadProtocol]>) -> Void) -> MXHTTPOperation? {
        var operation: MXHTTPOperation? = nil
        operation = allThreads(inRoom: roomId, from: nil, onlyParticipated: onlyParticipated) { response in
            guard let mainOperation = operation else {
                return
            }
            
            switch response {
            case .success(let value):
                if let nextBatch = value.nextBatch {
                    self.allThreads(inRoom: roomId, from: nextBatch, operation: mainOperation, onlyParticipated: onlyParticipated, threads: value.threads, completion: completion)
                } else {
                    completion(.success(value.threads))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
        
        return operation
    }

    //  MARK: - Private

    private func localThreads(inRoom roomId: String) -> [MXThreadProtocol] {
        //  sort threads so that the newer is the first
        return unsortedThreads(inRoom: roomId).sorted(by: <)
    }

    private func localParticipatedThreads(inRoom roomId: String) -> [MXThreadProtocol] {
        //  filter only participated threads and then sort threads so that the newer is the first
        return unsortedParticipatedThreads(inRoom: roomId).sorted(by: <)
    }

    private func thread(forRootEvent rootEvent: MXEvent, session: MXSession) -> MXThreadModel {
        var notificationCount: UInt = 0
        var highlightCount: UInt = 0
        if let store = session.store {
            notificationCount = store.localUnreadEventCount(rootEvent.roomId,
                                                            threadId: rootEvent.eventId,
                                                            withTypeIn: session.unreadEventTypes)
            let newEvents = store.newIncomingEvents(inRoom: rootEvent.roomId,
                                                    threadId: rootEvent.eventId,
                                                    withTypeIn: session.unreadEventTypes)
            highlightCount = UInt(newEvents.filter { $0.shouldBeHighlighted(inSession: session) }.count)
        }
        if let localThread = thread(withId: rootEvent.eventId) {
            notificationCount = max(notificationCount, localThread.notificationCount)
            highlightCount = max(highlightCount, localThread.highlightCount)
        }
        let thread = MXThreadModel(withRootEvent: rootEvent,
                                   notificationCount: notificationCount,
                                   highlightCount: highlightCount)
        //  workaround for https://github.com/matrix-org/synapse/issues/11753. Can be removed when that's fixed.
        if thread.numberOfReplies == 0, let localThread = self.thread(withId: rootEvent.eventId) {
            if let lastMessage = localThread.lastMessage {
                thread.updateLastMessage(lastMessage)
            }
            thread.updateNumberOfReplies(localThread.numberOfReplies)
        }
        return thread
    }

    private func handleInThreadEvent(_ event: MXEvent, direction: MXTimelineDirection, session: MXSession, completion: ((Bool) -> Void)?) {
        guard let threadId = event.threadId else {
            completion?(false)
            return
        }
        if let thread = thread(withId: threadId) {
            //  add event to the thread if found
            let handled = thread.addEvent(event, direction: direction)
            notifyDidUpdateThreads()
            completion?(handled)
        } else {
            //  create the thread for the first time
            let thread = MXThread(withSession: session, identifier: threadId, roomId: event.roomId)
            self.saveThread(thread)
            self.notifyDidCreateThread(thread, direction: direction)
            self.notifyDidUpdateThreads()
            let dispatchGroup = DispatchGroup()
            //  try to find the root event in the session store
            dispatchGroup.enter()
            session.event(withEventId: threadId, inRoom: event.roomId) { response in
                switch response {
                case .success(let rootEvent):
                    thread.addEvent(rootEvent, direction: direction)
                case .failure(let error):
                    MXLog.error("[MXThreadingService] handleInThreadEvent: root event not found", context: error)
                }
                dispatchGroup.leave()
            }

            dispatchGroup.notify(queue: .main) {
                let handled = thread.addEvent(event, direction: direction)
                self.notifyDidUpdateThreads()
                completion?(handled)
            }
        }
    }

    private func handleEditEvent(_ event: MXEvent, direction: MXTimelineDirection, session: MXSession, completion: ((Bool) -> Void)?) {
        guard let editedEventId = event.relatesTo?.eventId else {
            completion?(false)
            return
        }
        guard let editedEvent = session.store?.event(withEventId: editedEventId,
                                                  inRoom: event.roomId) else {
            completion?(false)
            return
        }

        handleEvent(editedEvent, direction: direction) { _ in
            guard let newEvent = editedEvent.editedEvent(fromReplacementEvent: event) else {
                completion?(false)
                return
            }
            if let threadId = editedEvent.threadId,
               let thread = self.thread(withId: threadId) {
                //  edited event is in a known thread
                let handled = thread.replaceEvent(withId: editedEventId, with: newEvent)
                self.notifyDidUpdateThreads()
                completion?(handled)
                return
            } else if let thread = self.thread(withId: editedEventId) {
                //  edited event is a thread root
                let handled = thread.replaceEvent(withId: editedEventId, with: newEvent)
                self.notifyDidUpdateThreads()
                completion?(handled)
                return
            }
            completion?(false)
        }
    }

    private func handleRedactionEvent(_ event: MXEvent, direction: MXTimelineDirection, session: MXSession, completion: ((Bool) -> Void)?) {
        guard direction == .forwards else {
            completion?(false)
            return
        }
        guard let redactedEventId = event.redacts,
              let redactedEvent = session.store?.event(withEventId: redactedEventId,
                                                       inRoom: event.roomId) else {
                  completion?(false)
                  return
              }

        session.decryptEvents([redactedEvent], inTimeline: nil) { _ in
            if let thread = self.thread(withId: redactedEventId) {
                //  event is a thread root
                let handled = thread.replaceEvent(withId: redactedEventId, with: redactedEvent)
                self.notifyDidUpdateThreads()
                completion?(handled)
            } else if let roomId = redactedEvent.roomId {
                var handled = false
                self.threads.filter { $1.roomId == roomId }.values.forEach {
                    let handledForThread = $0.redactEvent(withId: redactedEventId)
                    if handled == false {
                        handled = handledForThread
                    }
                }
                if handled {
                    self.notifyDidUpdateThreads()
                }
                completion?(handled)
            } else {
                completion?(false)
            }
        }
    }
    
    private func unsortedThreads(inRoom roomId: String) -> [MXThread] {
        return Array(threads.values).filter({ $0.roomId == roomId })
    }
    
    private func unsortedParticipatedThreads(inRoom roomId: String) -> [MXThread] {
        return Array(threads.values).filter({ $0.roomId == roomId && $0.isParticipated })
    }
    
    private func saveThread(_ thread: MXThread) {
        lockThreads.lock()
        defer { lockThreads.unlock() }
        threads[thread.id] = thread
    }
    
    // This method calls recursively the `allThreads` method until no next batch token is returned by the server
    // in order to aggregate all the threads of a room.
    private func allThreads(inRoom roomId: String,
                            from: String?,
                            operation: MXHTTPOperation,
                            onlyParticipated: Bool,
                            threads: [MXThreadProtocol],
                            completion: @escaping (MXResponse<[MXThreadProtocol]>) -> Void) {
        var newOperation: MXHTTPOperation? = nil
        newOperation = allThreads(inRoom: roomId, from: from, onlyParticipated: onlyParticipated, completion: { response in
            switch response {
            case .success(let value):
                let threads = threads + value.threads
                if let nextBatch = value.nextBatch {
                    self.allThreads(inRoom: roomId, from: nextBatch, operation: operation, onlyParticipated: onlyParticipated, threads: threads, completion: completion)
                } else {
                    completion(.success(threads))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        })
        
        guard let currentOperation = newOperation else {
            return
        }
        
        operation.mutate(to: currentOperation)
    }

    //  MARK: - Delegate
    
    /// Add delegate instance
    /// - Parameter delegate: delegate instance
    public func addDelegate(_ delegate: MXThreadingServiceDelegate) {
        multicastDelegate.addDelegate(delegate)
    }
    
    /// Remove delegate instance
    /// - Parameter delegate: delegate instance
    public func removeDelegate(_ delegate: MXThreadingServiceDelegate) {
        multicastDelegate.removeDelegate(delegate)
    }
    
    /// Remove all delegates
    public func removeAllDelegates() {
        multicastDelegate.removeAllDelegates()
    }
    
    private func notifyDidUpdateThreads() {
        multicastDelegate.invoke({ $0.threadingServiceDidUpdateThreads?(self) })
    }

    private func notifyDidCreateThread(_ thread: MXThread, direction: MXTimelineDirection) {
        multicastDelegate.invoke({ $0.threadingService?(self, didCreateNewThread: thread, direction: direction) })
    }
    
}

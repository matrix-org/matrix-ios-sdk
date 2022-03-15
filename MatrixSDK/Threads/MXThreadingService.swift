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
    public func handleJoinedRoomSync(_ roomSync: MXRoomSync) {
        guard let session = session else {
            //  session closed
            return
        }

        let events = roomSync.timeline.events
        session.decryptEvents(events, inTimeline: nil) { _ in
            let dispatchGroup = DispatchGroup()

            for event in events {
                dispatchGroup.enter()
                self.handleEvent(event, direction: .forwards) { _ in
                    dispatchGroup.leave()
                }
            }

            dispatchGroup.notify(queue: .main) {
                self.threads.values.forEach { $0.handleJoinedRoomSync(roomSync) }
            }
        }
    }

    /// Adds event to the related thread instance
    /// - Parameter event: event to be handled
    /// - Returns: true if the event handled, false otherwise
    @discardableResult
    public func handleEvent(_ event: MXEvent, direction: MXTimelineDirection) -> Bool {
        guard MXSDKOptions.sharedInstance().enableThreads else {
            //  threads disabled in the SDK
            return false
        }
        guard let session = session else {
            //  session closed
            return false
        }
        if event.isInThread() {
            //  event is in a thread
            return handleInThreadEvent(event, direction: direction, session: session)
        } else if let thread = thread(withId: event.eventId) {
            //  event is a thread root
            if thread.addEvent(event, direction: direction) {
                notifyDidUpdateThreads()
                return true
            }
        } else if event.isEdit() {
            return handleEditEvent(event, direction: direction, session: session)
        } else if event.eventType == .roomRedaction {
            return handleRedactionEvent(event, direction: direction, session: session)
        }
        return false
    }
    
    /// Get notifications count of threads in a room
    /// - Parameter roomId: Room identifier
    /// - Returns: Notifications count
    public func notificationsCount(forRoom roomId: String) -> MXThreadNotificationsCount {
        let notified = unsortedParticipatedThreads(inRoom: roomId).filter { $0.notificationCount > 0 }.count
        let highlighted = unsortedThreads(inRoom: roomId).filter { $0.highlightCount > 0 }.count
        return MXThreadNotificationsCount(numberOfNotifiedThreads: UInt(notified),
                                          numberOfHighlightedThreads: UInt(highlighted))
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
    public func allThreads(inRoom roomId: String,
                           onlyParticipated: Bool = false,
                           completion: @escaping (MXResponse<[MXThreadProtocol]>) -> Void) -> MXHTTPOperation? {
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
                //  homeserver supports threads
                let filter = MXRoomEventFilter()
                filter.relatedByTypes = [MXEventRelationTypeThread]
                if onlyParticipated {
                    filter.relatedBySenders = [session.myUserId]
                }
                let newOperation = session.matrixRestClient.messages(forRoom: roomId,
                                                                     from: "",
                                                                     direction: .backwards,
                                                                     limit: nil,
                                                                     filter: filter) { response in
                    switch response {
                    case .success(let paginationResponse):
                        guard let rootEvents = paginationResponse.chunk else {
                            completion(.success([]))
                            return
                        }

                        session.decryptEvents(rootEvents, inTimeline: nil) { _ in
                            let threads = rootEvents.map { self.thread(forRootEvent: $0, session: session) }.sorted(by: <)
                            let decryptionGroup = DispatchGroup()
                            for thread in threads {
                                if let rootEvent = rootEvents.first(where: { $0.eventId == thread.id }),
                                   let latestEvent = rootEvent.unsignedData.relations?.thread?.latestEvent {
                                    decryptionGroup.enter()
                                    session.decryptEvents([latestEvent], inTimeline: nil) { _ in
                                        thread.updateLastMessage(latestEvent)
                                        decryptionGroup.leave()
                                    }
                                }
                            }

                            decryptionGroup.notify(queue: .main) {
                                completion(.success(threads))
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
                    completion(.success(self.localParticipatedThreads(inRoom: roomId)))
                } else {
                    completion(.success(self.localThreads(inRoom: roomId)))
                }
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
        let notificationCount: UInt
        let highlightCount: UInt
        if let store = session.store {
            notificationCount = store.localUnreadEventCount(rootEvent.roomId,
                                                            threadId: rootEvent.eventId,
                                                            withTypeIn: session.unreadEventTypes)
            let newEvents = store.newIncomingEvents(inRoom: rootEvent.roomId,
                                                    threadId: rootEvent.eventId,
                                                    withTypeIn: session.unreadEventTypes)
            highlightCount = UInt(newEvents.filter { $0.shouldBeHighlighted(inSession: session) }.count)
        } else {
            notificationCount = 0
            highlightCount = 0
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

    @discardableResult
    private func handleInThreadEvent(_ event: MXEvent, direction: MXTimelineDirection, session: MXSession) -> Bool {
        guard let threadId = event.threadId else {
            return false
        }
        let handled: Bool
        if let thread = thread(withId: threadId) {
            //  add event to the thread if found
            handled = thread.addEvent(event, direction: direction)
        } else {
            //  create the thread for the first time
            let thread: MXThread
            //  try to find the root event in the session store
            if let rootEvent = session.store?.event(withEventId: threadId, inRoom: event.roomId) {
                thread = MXThread(withSession: session, rootEvent: rootEvent)
            } else {
                thread = MXThread(withSession: session, identifier: threadId, roomId: event.roomId)
            }
            handled = thread.addEvent(event, direction: direction)
            saveThread(thread)
            notifyDidCreateThread(thread, direction: direction)
        }
        notifyDidUpdateThreads()
        return handled
    }

    @discardableResult
    private func handleEditEvent(_ event: MXEvent, direction: MXTimelineDirection, session: MXSession) -> Bool {
        guard let editedEventId = event.relatesTo?.eventId else {
            return false
        }
        guard let editedEvent = session.store?.event(withEventId: editedEventId,
                                                  inRoom: event.roomId) else {
            return false
        }

        handleEvent(editedEvent, direction: direction)

        guard let newEvent = editedEvent.editedEvent(fromReplacementEvent: event) else {
            return false
        }
        if let threadId = editedEvent.threadId,
           let thread = thread(withId: threadId) {
            //  edited event is in a known thread
            let handled = thread.replaceEvent(withId: editedEventId, with: newEvent)
            notifyDidUpdateThreads()
            return handled
        } else if let thread = thread(withId: editedEventId) {
            //  edited event is a thread root
            let handled = thread.replaceEvent(withId: editedEventId, with: newEvent)
            notifyDidUpdateThreads()
            return handled
        }
        return false
    }

    @discardableResult
    private func handleRedactionEvent(_ event: MXEvent, direction: MXTimelineDirection, session: MXSession) -> Bool {
        guard direction == .forwards else {
            return false
        }
        if let redactedEventId = event.redacts,
           let thread = thread(withId: redactedEventId),
           let newEvent = session.store?.event(withEventId: redactedEventId,
                                               inRoom: event.roomId) {
            //  event is a thread root
            let handled = thread.replaceEvent(withId: redactedEventId, with: newEvent)
            notifyDidUpdateThreads()
            return handled
        }
        return false
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

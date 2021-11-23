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
/// Thread instance. Use `MXThreadingService` to access threads.
public class MXThread: NSObject {
    
    /// Session instance
    public private(set) weak var session: MXSession?
    
    /// Identifier of a thread. It's equal to identifier of the root event
    public let identifier: String
    
    /// Identifier of the room, in which the thread is
    public let roomId: String
    
    private var eventsMap: [String: MXEvent] = [:]
    
    internal init(withSession session: MXSession,
                  identifier: String,
                  roomId: String) {
        self.session = session
        self.identifier = identifier
        self.roomId = roomId
        super.init()
    }
    
    internal init(withSession session: MXSession,
                  rootEvent: MXEvent) {
        self.session = session
        self.identifier = rootEvent.eventId
        self.roomId = rootEvent.roomId
        self.eventsMap = [rootEvent.eventId: rootEvent]
        super.init()
    }
    
    internal func addEvent(_ event: MXEvent) {
        guard eventsMap[event.eventId] == nil else {
            //  do not re-add the event
            return
        }
        eventsMap[event.eventId] = event
    }
    
    /// Flag indicating the current user participated in the thread
    public var isParticipated: Bool {
        guard let session = session else {
            return false
        }
        return eventsMap.values.first(where: { $0.sender == session.myUserId }) != nil
    }
    
    /// Root message of the thread
    public var rootMessage: MXEvent? {
        return eventsMap[identifier]
    }
    
    /// Last message of the thread
    public var lastMessage: MXEvent? {
        //  sort events so that the older is the first
        return eventsMap.values.sorted(by: >).last
    }
    
    /// Number of replies in the thread. Does not count the root event
    public var numberOfReplies: Int {
        return eventsMap.filter({ $0 != identifier && $1.isInThread() }).count
    }
    
    /// Fetches all replies in a thread. Not used right now
    /// - Parameter completion: Completion block to be called at the end of the progress
    public func allReplies(completion: @escaping (MXResponse<[MXEvent]>) -> Void) {
        guard let session = session else {
            completion(.failure(MXThreadingServiceError.sessionNotFound))
            return
        }
        
        session.matrixRestClient.relations(forEvent: identifier,
                                           inRoom: roomId,
                                           relationType: MXEventRelationTypeThread,
                                           eventType: nil,
                                           from: nil,
                                           limit: nil) { response in
            switch response {
            case .success(let aggregatedResponse):
                completion(.success(aggregatedResponse.chunk))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

//  MARK: - Comparable

extension MXThread: Comparable {
    
    /// Comparator for thread instances, to compare two threads according to their last message time.
    /// - Parameters:
    ///   - lhs: left operand
    ///   - rhs: right operand
    /// - Returns: true if left operand's last message is newer than the right operand's last message, false otherwise
    public static func < (lhs: MXThread, rhs: MXThread) -> Bool {
        //  thread will be 'smaller' than an other thread if it's last message is newer
        let leftLastMessage = lhs.lastMessage
        let rightLastMessage = rhs.lastMessage
        if let leftLastMessage = leftLastMessage {
            if let rightLastMessage = rightLastMessage {
                return leftLastMessage < rightLastMessage
            } else {
                return false
            }
        } else if rightLastMessage != nil {
            return true
        } else {
            return false
        }
    }
    
}

//  MARK: - MXEvent Extension

extension MXEvent: Comparable {
    
    public static func < (lhs: MXEvent, rhs: MXEvent) -> Bool {
        //  event will be 'smaller' than an other event if it's newer
        return lhs.age < rhs.age
    }
    
}

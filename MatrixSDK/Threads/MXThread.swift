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
    public let id: String
    
    /// Identifier of the room that the thread is in.
    public let roomId: String
    
    public private(set) var hasRootEvent: Bool
    
    private var eventsMap: [String: MXEvent] = [:]
    
    internal init(withSession session: MXSession,
                  identifier: String,
                  roomId: String) {
        self.session = session
        self.id = identifier
        self.roomId = roomId
        self.hasRootEvent = false
        super.init()
    }
    
    internal init(withSession session: MXSession,
                  rootEvent: MXEvent) {
        self.session = session
        self.id = rootEvent.eventId
        self.roomId = rootEvent.roomId
        self.hasRootEvent = true
        self.eventsMap = [rootEvent.eventId: rootEvent]
        super.init()
    }
    
    internal func addEvent(_ event: MXEvent) {
        guard eventsMap[event.eventId] == nil else {
            //  do not re-add the event
            return
        }
        eventsMap[event.eventId] = event
        
        if event.eventId == id {
            //  if root event is added later, update the flag
            hasRootEvent = true
        }
    }
    
    /// Last message of the thread
    public var lastMessage: MXEvent? {
        //  sort events by their age: so older events will be at the beginning in the array
        return eventsMap.values.sorted(by: >).last
    }
    
    /// Number of replies in the thread. Does not count the root event
    public var numberOfReplies: Int {
        return eventsMap.filter({ $0 != id && $1.isInThread() }).count
    }
    
    /// Fetches all replies in a thread. Not used right now
    /// - Parameter completion: Completion block to be called at the end of the progress
    public func allReplies(completion: @escaping (MXResponse<[MXEvent]>) -> Void) {
        guard let session = session else {
            completion(.failure(MXThreadingServiceError.sessionNotFound))
            return
        }
        
        session.matrixRestClient.relations(forEvent: id,
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

extension MXThread: Identifiable {}

//  MARK: - MXEvent Extension

extension MXEvent: Comparable {
    
    public static func < (lhs: MXEvent, rhs: MXEvent) -> Bool {
        //  event will be 'smaller' than an other event if it's newer
        if lhs.originServerTs != NSNotFound && rhs.originServerTs != NSNotFound {
            return lhs.compareOriginServerTs(rhs) == .orderedAscending
        }
        return lhs.age < rhs.age
    }
    
}

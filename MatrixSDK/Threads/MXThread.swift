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
public class MXThread: NSObject {
    
    private weak var session: MXSession?
    
    public let identifier: String
    
    public let roomId: String
    
    public private(set) var hasRootEvent: Bool
    
    public private(set) var events: [MXEvent] = []
    
    internal init(withSession session: MXSession,
                  identifier: String,
                  roomId: String) {
        self.session = session
        self.identifier = identifier
        self.roomId = roomId
        self.hasRootEvent = false
        super.init()
    }
    
    internal init(withSession session: MXSession,
                  rootEvent: MXEvent) {
        self.session = session
        self.identifier = rootEvent.eventId
        self.roomId = rootEvent.roomId
        self.hasRootEvent = true
        self.events = [rootEvent]
        super.init()
    }
    
    public func addEvent(_ event: MXEvent) {
        self.events.append(event)
        
        if event.eventId == identifier {
            //  if root event is added later
            self.hasRootEvent = true
        }
    }
    
    public var lastMessage: MXEvent? {
        return events.last
    }
    
    public var numberOfReplies: Int {
        if hasRootEvent {
            //  do not count the root event
            return events.count - 1
        } else {
            //  count all events
            return events.count
        }
    }
    
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

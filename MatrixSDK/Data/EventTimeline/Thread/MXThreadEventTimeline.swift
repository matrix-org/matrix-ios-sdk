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
    
    public var isLiveTimeline: Bool
    
    public var roomEventFilter: MXRoomEventFilter?
    
    public var state: MXRoomState?
    
    public required init(room: MXRoom, andInitialEventId initialEventId: String?) {
        self.timelineId = UUID().uuidString
        self.initialEventId = initialEventId
        self.isLiveTimeline = true
        super.init()
    }
    
    public required init(room: MXRoom, initialEventId: String?, andStore store: MXStore) {
        self.timelineId = UUID().uuidString
        self.initialEventId = initialEventId
        self.isLiveTimeline = true
        super.init()
    }
    
    public func initialiseState(_ stateEvents: [MXEvent]) {
        
    }
    
    public func destroy() {
        
    }
    
    public func canPaginate(_ direction: MXTimelineDirection) -> Bool {
        return false
    }
    
    public func resetPagination() {
        
    }
    
    public func __resetPaginationAroundInitialEvent(withLimit limit: UInt, success: @escaping () -> Void, failure: @escaping (Error) -> Void) -> MXHTTPOperation {
        return MXHTTPOperation()
    }
    
    public func __paginate(_ numItems: UInt, direction: MXTimelineDirection, onlyFromStore: Bool, complete: @escaping () -> Void, failure: @escaping (Error) -> Void) -> MXHTTPOperation {
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
        return MXEventListener()
    }
    
    public func __listen(toEventsOfTypes types: [String]?, onEvent: @escaping MXOnRoomEvent) -> MXEventListener {
        return MXEventListener()
    }
    
    public func remove(_ listener: MXEventListener) {
        
    }
    
    public func removeAllListeners() {
        
    }
    
    public func notifyListeners(_ event: MXEvent, direction: MXTimelineDirection) {
        
    }
    
    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }
    
}

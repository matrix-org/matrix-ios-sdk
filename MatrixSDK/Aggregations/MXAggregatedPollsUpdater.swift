// 
// Copyright 2022 The Matrix.org Foundation C.I.C
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
/// `MXAggregatedPollsUpdater` populates the local database with poll events when some of them may be missing.
/// This can happen for example when a user joins a room with an ongoing poll.
/// In this case `poll.start` and `poll.response` events may be missing causing incorrect rendering of polls on the timeline.
/// This type fetches all the related events of a poll when a `poll.end` event triggers.
public final class MXAggregatedPollsUpdater: NSObject {
    private let session: MXSession
    private let store: MXStore
    
    public init(session: MXSession, store: MXStore) {
        self.session = session
        self.store = store
    }
    
    public func refreshPoll(after event: MXEvent) {
        // the poll refresh is meant to be done at the end of a poll
        guard
            event.eventType == .pollEnd,
            let relatedTo = event.relatesTo,
            relatedTo.relationType == MXEventRelationTypeReference,
            let pollStartEventId = relatedTo.eventId
        else {
            return
        }
        
        // clients having the poll_started event are supposed to have all the history in between because of the /sync api
        guard store.eventExists(withEventId: pollStartEventId, inRoom: event.roomId) == false else {
            return
        }
        
        session.matrixRestClient.relations(
            forEvent: pollStartEventId,
            inRoom: event.roomId,
            relationType: MXEventRelationTypeReference,
            eventType: nil,
            from: nil,
            direction: MXTimelineDirection.backwards,
            limit: nil) { [weak self] response in
                switch response {
                case .success(let response):
                    self?.session.store(response: response)
                case .failure:
                    break
                }
            }
    }
}

private extension MXSession {
    func store(response: MXAggregationPaginatedResponse) {
        // reverse chronological order
        let allEvents = response.chunk + response.originalEventArray
        storeIfNeeded(events: allEvents)
    }
    
    func storeIfNeeded(events: [MXEvent]) {
       let eventsToStore = events
            .filter { event in
                store.eventExists(withEventId: event.eventId, inRoom: event.roomId) == false
            }
        
        for event in eventsToStore {
            store.storeEvent(forRoom: event.roomId, event: event, direction: .backwards)
        }

        if eventsToStore.isEmpty == false {
            store.commit?()
        }
    }
}

private extension MXAggregationPaginatedResponse {
    var originalEventArray: [MXEvent] {
        originalEvent.map { [$0] } ?? []
    }
}

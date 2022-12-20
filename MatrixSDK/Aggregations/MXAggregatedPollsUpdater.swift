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
public final class MXAggregatedPollsUpdater: NSObject {
    private let session: MXSession
    private let store: MXStore
    
    init(session: MXSession, store: MXStore) {
        self.session = session
        self.store = store
    }
    
    public func refreshPoll(after event: MXEvent) {
        // the poll refresh is meant to be done at the end of a poll
        guard
            event.eventType == .pollEnd,
            event.relatesTo.relationType == MXEventRelationTypeReference,
            let pollStartEventId = event.relatesTo.eventId
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
                    self?.session.decryptAndStore(response: response)
                case .failure:
                    break
                }
            }
    }
}

private extension MXSession {
    func decryptAndStore(response: MXAggregationPaginatedResponse) {
        let allEvents = response.chunk + response.originalEventArray
        
        let eventsToDecrypt = allEvents
            .filter {
                $0.isEncrypted && $0.clear == nil
            }
         
        decryptEvents(eventsToDecrypt, inTimeline: nil) { [weak self] failedEvents in
            guard let self = self else {
                return
            }
            
            allEvents
                .filter { event in
                    !event.isEncrypted && !self.store.eventExists(withEventId: event.eventId, inRoom: event.roomId)
                }
                .forEach { event in
                    self.store.storeEvent(forRoom: event.roomId, event: event, direction: .backwards)
                }
        }
    }
}

private extension MXAggregationPaginatedResponse {
    var originalEventArray: [MXEvent] {
        originalEvent.map { [$0] } ?? []
    }
}

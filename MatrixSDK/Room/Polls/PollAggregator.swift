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

/// PollAggregator errors 
enum PollAggregatorError: Error {
    case invalidPollStartEvent
}

protocol PollAggregatorDelegate: AnyObject {
    func pollAggregatorDidStartLoading(_ aggregator: PollAggregator)
    func pollAggregatorDidEndLoading(_ aggregator: PollAggregator)
    func pollAggregator(_ aggregator: PollAggregator, didFailWithError: Error)
    func pollAggregatorDidUpdateData(_ aggregator: PollAggregator)
}

/**
 Responsible for building poll models out of the original poll start event and listen to replies.
 It will listen for PollResponse and PollEnd events on the live timline and update the built models accordingly.
 I will also listen for `mxRoomDidFlushData` and reload all data to avoid gappy sync problems
*/

class PollAggregator {
    
    private let session: MXSession
    private let room: MXRoom
    private let pollStartEvent: MXEvent
    private let pollStartEventContent: MXEventContentPollStart
    private let pollBuilder: PollBuilder
    
    private var eventListener: Any!
    private var events: [MXEvent] = []
    
    private(set) var poll: PollProtocol! {
        didSet {
            delegate?.pollAggregatorDidUpdateData(self)
        }
    }
    
    var delegate: PollAggregatorDelegate?
    
    deinit {
        room.removeListener(eventListener)
    }
    
    init(session: MXSession, room: MXRoom, pollStartEvent: MXEvent) throws {
        self.session = session
        self.room = room
        self.pollStartEvent = pollStartEvent
        
        guard let pollStartEventContent = MXEventContentPollStart(fromJSON: pollStartEvent.content) else {
            throw PollAggregatorError.invalidPollStartEvent
        }
        
        self.pollStartEventContent = pollStartEventContent
        
        pollBuilder = PollBuilder()
        
        poll = pollBuilder.build(pollStartEventContent: self.pollStartEventContent, events: self.events)
        
        reloadData()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomDataFlush), name: NSNotification.Name.mxRoomDidFlushData, object: self.room)
    }
    
    @objc private func handleRoomDataFlush(sender: Notification) {
        guard let room = sender.object as? MXRoom, room == self.room else {
            return
        }
        
        reloadData()
    }
    
    private func reloadData() {
        delegate?.pollAggregatorDidStartLoading(self)
        session.aggregations.referenceEvents(forEvent: pollStartEvent.eventId, inRoom: room.roomId, from: nil, limit: -1) { [weak self] response in
            guard let self = self else {
                return
            }
            
            self.events.removeAll()
            
            self.events.append(contentsOf: response.chunk)
            
            self.eventListener = self.room.listen(toEventsOfTypes: [kMXEventTypeStringPollResponse, kMXEventTypeStringPollEnd]) { [weak self] event, direction, state in
                guard let self = self, let event = event else {
                    return
                }
                
                self.events.append(event)
                
                self.poll = self.pollBuilder.build(pollStartEventContent: self.pollStartEventContent, events: self.events)
            } as Any
            
            self.poll = self.pollBuilder.build(pollStartEventContent: self.pollStartEventContent, events: self.events)
            
            self.delegate?.pollAggregatorDidEndLoading(self)
            
        } failure: { [weak self] error in
            guard let self = self else {
                return
            }
            
            self.delegate?.pollAggregator(self, didFailWithError: error)
        }
    }
}

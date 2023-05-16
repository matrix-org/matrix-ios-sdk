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
public enum PollAggregatorError: Error {
    case invalidPollStartEvent
}

public protocol PollAggregatorDelegate: AnyObject {
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

public class PollAggregator {
    
    private struct Constants {
        static let minAnswerOptionCount = 2
    }
    
    private let session: MXSession
    private let room: MXRoom
    private let pollStartEventId: String
    private let pollBuilder: PollBuilder
    
    private var pollStartedEvent: MXEvent!
    private var pollStartEventContent: MXEventContentPollStart!
    
    private var referenceEventsListener: Any?
    private var editEventsListener: Any?
    
    private var events: [MXEvent] = []
    private var hasBeenEdited = false
    
    public private(set) var poll: PollProtocol? {
        didSet {
            delegate?.pollAggregatorDidUpdateData(self)
        }
    }
    
    public weak var delegate: PollAggregatorDelegate?
    
    deinit {
        if let referenceEventsListener = referenceEventsListener {
            room.removeListener(referenceEventsListener)
        }
        
        if let editEventsListener = editEventsListener {
            session.aggregations.removeListener(editEventsListener)
        }
    }
    
    public convenience init(session: MXSession, room: MXRoom, pollEvent: MXEvent, delegate: PollAggregatorDelegate? = nil) throws {
        var pollStartEventId: String?
        
        switch pollEvent.eventType {
        case .pollStart:
            pollStartEventId = pollEvent.eventId
        case .pollEnd:
            pollStartEventId = pollEvent.relatesTo?.eventId
        default:
            pollStartEventId = nil
        }
        
        guard let pollStartEventId = pollStartEventId else {
            throw PollAggregatorError.invalidPollStartEvent
        }
        
        self.init(session: session, room: room, pollStartEventId: pollStartEventId, delegate: delegate)
    }
    
    public init(session: MXSession, room: MXRoom, pollStartEventId: String, delegate: PollAggregatorDelegate? = nil) {
        self.session = session
        self.room = room
        self.pollStartEventId = pollStartEventId
        self.pollBuilder = PollBuilder()
        self.delegate = delegate
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleRoomDataFlush), name: .mxRoomDidFlushData, object: self.room)
        setupEditListener()
        buildPollStartContent()
        
        reloadPollData()
    }
    
    private func setupEditListener() {
        editEventsListener = session.aggregations.listenToEditsUpdate(inRoom: self.room.roomId) { [weak self] event in
            guard let self = self,
                  self.pollStartEventId == event.relatesTo?.eventId
            else {
                return
            }
            
            self.buildPollStartContent()
        }
    }
    
    private func buildPollStartContent() {
        let event = session.store.event(withEventId: pollStartEventId, inRoom: room.roomId)
        tryUpdatePollStartedEvent(with: event)
        if let pollStartedEvent = pollStartedEvent {
            poll = pollBuilder.build(pollStartEventContent: pollStartEventContent,
                                     pollStartEvent: pollStartedEvent,
                                     events: events,
                                     currentUserIdentifier: session.myUserId,
                                     hasBeenEdited: hasBeenEdited)
        }
    }

    private func tryUpdatePollStartedEvent(with event: MXEvent?) {
        guard
            let event = event,
            let eventContent = MXEventContentPollStart(fromJSON: event.content),
            eventContent.answerOptions.count >= Constants.minAnswerOptionCount
        else {
            delegate?.pollAggregator(self, didFailWithError: PollAggregatorError.invalidPollStartEvent)
            return
        }
        
        pollStartedEvent = event
        pollStartEventContent = eventContent
        hasBeenEdited = (event.unsignedData.relations?.replace != nil)
    }
    
    @objc private func handleRoomDataFlush(sender: Notification) {
        guard let room = sender.object as? MXRoom, room == self.room else {
            return
        }
        
        reloadPollData()
    }
    
    private func reloadPollData() {
        delegate?.pollAggregatorDidStartLoading(self)
        
        session.aggregations.referenceEvents(forEvent: pollStartEventId, inRoom: room.roomId, from: nil, limit: -1) { [weak self] response in
            guard let self = self else {
                return
            }
            
            self.tryUpdatePollStartedEvent(with: response.originalEvent)
            if self.pollStartedEvent == nil {
                return
            }
            
            self.events.removeAll()
            self.events.append(contentsOf: response.chunk)
            
            let eventTypes = [kMXEventTypeStringPollResponse, kMXEventTypeStringPollResponseMSC3381, kMXEventTypeStringPollEnd, kMXEventTypeStringPollEndMSC3381]
            self.referenceEventsListener = self.room.listen(toEventsOfTypes: eventTypes) { [weak self] event, direction, state in
                guard
                    let self = self,
                    let relatedEventId = event.relatesTo?.eventId,
                    relatedEventId == self.pollStartEventId
                else {
                    return
                }
                
                self.events.append(event)
                
                self.poll = self.pollBuilder.build(pollStartEventContent: self.pollStartEventContent,
                                                   pollStartEvent: self.pollStartedEvent,
                                                   events: self.events,
                                                   currentUserIdentifier: self.session.myUserId,
                                                   hasBeenEdited: self.hasBeenEdited)
            } as Any

            self.poll = self.pollBuilder.build(pollStartEventContent: self.pollStartEventContent,
                                               pollStartEvent: self.pollStartedEvent,
                                               events: self.events,
                                               currentUserIdentifier: self.session.myUserId,
                                               hasBeenEdited: self.hasBeenEdited)
            
            self.delegate?.pollAggregatorDidEndLoading(self)
            
        } failure: { [weak self] error in
            guard let self = self else {
                return
            }
            
            self.delegate?.pollAggregator(self, didFailWithError: error)
        }
    }
}

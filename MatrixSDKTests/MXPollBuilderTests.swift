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

class MXPollBuilderTest: XCTestCase {
    
    let builder = PollBuilder()
    
    func testBaseCase() {
        var events = [MXEvent]()
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Alice", answerIdentifiers: ["1"]))!)
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", answerIdentifiers: ["1"]))!)
        
        let poll = builder.build(pollStartEventContent: pollStartEventContent(maxSelections: 7), pollStartEvent: pollStartedEvent(), events: events, currentUserIdentifier: "")
        XCTAssertEqual(poll.maxAllowedSelections, 7)
        XCTAssertEqual(poll.text, "Question")
        XCTAssertEqual(poll.kind, .disclosed)
        
        XCTAssertEqual(poll.answerOptions.first?.id, "1")
        XCTAssertEqual(poll.answerOptions.first?.text, "First answer")
        XCTAssertEqual(poll.answerOptions.first?.count, 2)
        
        XCTAssertEqual(poll.answerOptions.last?.id, "2")
        XCTAssertEqual(poll.answerOptions.last?.text, "Second answer")
        XCTAssertEqual(poll.answerOptions.last?.count, 0)
        
        XCTAssertEqual(poll.id, "$eventId")
        XCTAssertEqual(poll.startDate, Date(timeIntervalSince1970: 0))
    }
    
    func testSpoiledResponseEmpty() {
        var events = [MXEvent]()
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", timestamp: 0, answerIdentifiers: ["1"]))!)
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", timestamp: 1, answerIdentifiers: []))!)
        
        let poll = builder.build(pollStartEventContent: pollStartEventContent(), pollStartEvent: pollStartedEvent(), events: events, currentUserIdentifier: "")
        XCTAssertEqual(poll.answerOptions.first?.count, 0)
        XCTAssertEqual(poll.answerOptions.last?.count, 0)
    }
    
    func testSpoiledResponseTooManyAnswer() {
        var events = [MXEvent]()
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", timestamp: 0, answerIdentifiers: ["1"]))!)
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", timestamp: 1, answerIdentifiers: ["1", "2"]))!)
        
        let poll = builder.build(pollStartEventContent: pollStartEventContent(), pollStartEvent: pollStartedEvent(), events: events, currentUserIdentifier: "")
        XCTAssertEqual(poll.answerOptions.first?.count, 0)
        XCTAssertEqual(poll.answerOptions.last?.count, 0)
    }
    
    func testSpoiledAnswersInvalidAnswerIdentifiers() {
        var events = [MXEvent]()
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", timestamp: 0, answerIdentifiers: ["1"]))!)
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", timestamp: 1, answerIdentifiers: ["1", "2", "3"]))!)
        
        let poll = builder.build(pollStartEventContent: pollStartEventContent(), pollStartEvent: pollStartedEvent(), events: events, currentUserIdentifier: "")
        XCTAssertEqual(poll.answerOptions.first?.count, 0)
        XCTAssertEqual(poll.answerOptions.last?.count, 0)
    }
    
    func testRepeatedAnswerIdentifiers() {
        var events = [MXEvent]()
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", answerIdentifiers: ["1", "1", "1"]))!)
        
        let poll = builder.build(pollStartEventContent: pollStartEventContent(maxSelections: 100), pollStartEvent: pollStartedEvent(), events: events, currentUserIdentifier: "")
        XCTAssertEqual(poll.answerOptions.first?.count, 1)
        XCTAssertEqual(poll.answerOptions.last?.count, 0)
    }
    
    func testRandomlyRepeatedAnswerIdentifiers() {
        var events = [MXEvent]()
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", answerIdentifiers: ["1", "1", "2", "1", "2", "2", "1", "2"]))!)
        
        let poll = builder.build(pollStartEventContent: pollStartEventContent(maxSelections: 100), pollStartEvent: pollStartedEvent(), events: events, currentUserIdentifier: "")
        XCTAssertEqual(poll.answerOptions.first?.count, 1)
        XCTAssertEqual(poll.answerOptions.last?.count, 1)
    }
    
    func testAnswerOrder() {
        var events = [MXEvent]()
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", timestamp: 0, answerIdentifiers: ["1"]))!)
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", timestamp: 4, answerIdentifiers: ["2"]))!)
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", timestamp: 2, answerIdentifiers: ["1"]))!)
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", timestamp: 1, answerIdentifiers: []))!) // Too few
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", timestamp: 3, answerIdentifiers: ["1", "2"]))!) // Too many
        
        let poll = builder.build(pollStartEventContent: pollStartEventContent(), pollStartEvent: pollStartedEvent(), events: events, currentUserIdentifier: "")
        XCTAssertEqual(poll.answerOptions.first?.count, 0)
        XCTAssertEqual(poll.answerOptions.last?.count, 1)
    }
    
    func testClosedPoll() {
     
        var events = [MXEvent]()
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", timestamp: 0, answerIdentifiers: ["1"]))!)
        
        events.append(MXEvent(fromJSON: pollEndEvent(timestamp: 1)))
        
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", timestamp: 10, answerIdentifiers: ["1"]))!)
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", timestamp: 10, answerIdentifiers: []))!)
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Alice", timestamp:10, answerIdentifiers: ["1", "2"]))!)
        
        let poll = builder.build(pollStartEventContent: pollStartEventContent(maxSelections: 10), pollStartEvent: pollStartedEvent(), events: events, currentUserIdentifier: "")
        
        XCTAssert(poll.isClosed)
        
        XCTAssertEqual(poll.answerOptions.first!.count, 1)
        XCTAssert(poll.answerOptions.first!.isWinner)
        
        XCTAssertEqual(poll.answerOptions.last!.count, 0)
        XCTAssert(!poll.answerOptions.last!.isWinner)
    }
    
    func testCurrentUserSingleSelection() {
        var events = [MXEvent]()
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", answerIdentifiers: ["1"]))!)
        
        let poll = builder.build(pollStartEventContent: pollStartEventContent(maxSelections: 7), pollStartEvent: pollStartedEvent(), events: events, currentUserIdentifier: "Bob")
        XCTAssertEqual(poll.answerOptions.first?.isCurrentUserSelection, true)
        XCTAssertEqual(poll.answerOptions.last?.isCurrentUserSelection, false)
    }
    
    func testCurrentUserMultlipleSelection() {
        var events = [MXEvent]()
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", timestamp: 0, answerIdentifiers: ["1"]))!)
        events.append(MXEvent(fromJSON: pollResponseEventWithSender("Bob", timestamp: 1, answerIdentifiers: ["2", "1"]))!)
        
        let poll = builder.build(pollStartEventContent: pollStartEventContent(maxSelections: 7), pollStartEvent: pollStartedEvent(), events: events, currentUserIdentifier: "Bob")
        XCTAssertEqual(poll.answerOptions.first?.isCurrentUserSelection, true)
        XCTAssertEqual(poll.answerOptions.last?.isCurrentUserSelection, true)
    }
    
    // MARK: - Private
    
    private func pollStartEventContent(maxSelections: UInt = 1) -> MXEventContentPollStart {
        let answerOptions = [MXEventContentPollStartAnswerOption(uuid: "1", text: "First answer"),
                             MXEventContentPollStartAnswerOption(uuid: "2", text: "Second answer")]
        
        return MXEventContentPollStart(question: "Question",
                                       kind: kMXMessageContentKeyExtensiblePollKindDisclosed,
                                       maxSelections: NSNumber(value: maxSelections),
                                       answerOptions: answerOptions)
    }
    
    private func pollStartedEvent() -> MXEvent {
        .init(fromJSON: pollResponseEventWithSender("Bob", answerIdentifiers: ["1", "2"]))
    }
    
    private func pollResponseEventWithSender(_ sender: String, timestamp: Int = 0, answerIdentifiers:[String]) -> [String: Any] {
        return [
            "event_id": "$eventId",
            "type": kMXEventTypeStringPollResponse,
            "sender": sender,
            "origin_server_ts": timestamp,
            "content": [kMXMessageContentKeyExtensiblePollResponse: [kMXMessageContentKeyExtensiblePollAnswers: answerIdentifiers]]
        ]
    }
    
    private func pollEndEvent(timestamp: Int = 0) -> [String: Any] {
        return [
            "event_id": "$eventId",
            "type": kMXEventTypeStringPollEnd,
            "origin_server_ts": timestamp,
            "content": [kMXMessageContentKeyExtensiblePollEnd: [:]]
        ]
    }
}

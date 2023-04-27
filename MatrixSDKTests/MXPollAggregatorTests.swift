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

class MXPollAggregatorTest: XCTestCase {
    private var matrixSDKTestsData: MatrixSDKTestsData!
    private var matrixSDKTestsE2EData: MatrixSDKTestsE2EData!
    private var pollAggregator: PollAggregator!
    private var delegate: PollAggregatorBlockWrapper!
    private var isFirstDelegateUpdate: Bool = true
    
    override func setUp() {
        super.setUp()
        matrixSDKTestsData = MatrixSDKTestsData()
        matrixSDKTestsE2EData = MatrixSDKTestsE2EData(matrixSDKTestsData: matrixSDKTestsData)
        isFirstDelegateUpdate = true
    }
    
    override func tearDown() {
        matrixSDKTestsData = nil
        matrixSDKTestsE2EData = nil
        delegate = nil
        super.tearDown()
    }
        
    func testAggregations() {
        self.createScenarioForBobAndAlice { bobSession, aliceSession, bobRoom, aliceRoom, pollStartEvent, expectation in
            self.delegate = PollAggregatorBlockWrapper(dataUpdateCallback: { pollAggregator in
                XCTAssertEqual(self.pollAggregator.poll?.answerOptions.first!.count, 2)
                XCTAssertEqual(self.pollAggregator.poll?.answerOptions.last!.count, 0)
                expectation.fulfill()
            })
            
            self.pollAggregator = PollAggregator(session: bobSession, room: bobRoom, pollStartEventId: pollStartEvent.eventId)
        
            let dispatchGroup = DispatchGroup()
            
            for _ in 1...5 {
                dispatchGroup.enter()
                bobRoom.sendPollResponse(for: pollStartEvent, withAnswerIdentifiers: ["2"], threadId:nil, localEcho: nil) { _ in
                    dispatchGroup.leave()
                } failure: { error in
                    XCTFail("The operation should not fail - NSError: \(String(describing: error))")
                }
            }
            
            dispatchGroup.enter()
            bobRoom.sendPollResponse(for: pollStartEvent, withAnswerIdentifiers: ["1"], threadId:nil, localEcho: nil) { _ in
                dispatchGroup.leave()
            } failure: { error in
                XCTFail("The operation should not fail - NSError: \(String(describing: error))")
            }
            
            dispatchGroup.notify(queue: .main) {
                self.pollAggregator.delegate = self.delegate
            }
        }
    }
    
    func testSessionPausing() {
        self.createScenarioForBobAndAlice { bobSession, aliceSession, bobRoom, aliceRoom, pollStartEvent, expectation in
            let delegate = PollAggregatorBlockWrapper(dataUpdateCallback: { aggregator in
                XCTAssertEqual(aggregator.poll?.answerOptions.first!.count, 2)
                XCTAssertEqual(aggregator.poll?.answerOptions.last!.count, 0)
            })
            
            self.pollAggregator = PollAggregator(session: bobSession, room: bobRoom, pollStartEventId: pollStartEvent.eventId)
            
            XCTAssertEqual(self.pollAggregator.poll?.answerOptions.first!.count, 1) // One from Alice
            XCTAssertEqual(self.pollAggregator.poll?.answerOptions.last!.count, 0)
            
            bobSession.pause()
            
            self.pollAggregator.delegate = delegate
            
            bobRoom.sendPollResponse(for: pollStartEvent, withAnswerIdentifiers: ["1"], threadId:nil, localEcho: nil) { _ in
                bobSession.resume {
                    expectation.fulfill()
                }
            } failure: { error in
                XCTFail("The operation should not fail - NSError: \(String(describing: error))")
            }
        }
    }
    
    func testGappySync() {
        self.createScenarioForBobAndAlice { bobSession, aliceSession, bobRoom, aliceRoom, pollStartEvent, expectation in
            self.pollAggregator = PollAggregator(session: bobSession, room: bobRoom, pollStartEventId: pollStartEvent.eventId)
            
            self.delegate = PollAggregatorBlockWrapper(dataUpdateCallback: { aggregator in
                XCTAssertEqual(aggregator.poll?.answerOptions.first!.count, 2) // One from Bob and one from Alice
                XCTAssertEqual(aggregator.poll?.answerOptions.last!.count, 1) // One from Alice
                expectation.fulfill()
            })
            
            XCTAssertEqual(self.pollAggregator.poll?.answerOptions.first!.count, 1) // One from Alice
            XCTAssertEqual(self.pollAggregator.poll?.answerOptions.last!.count, 0)
            
            bobSession.pause()
            
            self.matrixSDKTestsData.for(bobSession.matrixRestClient, andRoom: bobRoom.roomId, sendMessages: 50, testCase: self) {
                bobRoom.sendPollResponse(for: pollStartEvent, withAnswerIdentifiers: ["1"], threadId:nil, localEcho: nil) { _ in
                    aliceRoom.sendPollResponse(for: pollStartEvent, withAnswerIdentifiers: ["1", "2"], threadId:nil, localEcho: nil) { _ in
                        self.matrixSDKTestsData.for(aliceSession.matrixRestClient, andRoom: aliceRoom.roomId, sendMessages: 50, testCase: self) {
                            self.pollAggregator.delegate = self.delegate
                            
                            bobSession.resume {
                                
                            }
                        }
                    } failure: { error in
                        XCTFail("The operation should not fail - NSError: \(String(describing: error))")
                    }
                    
                } failure: { error in
                    XCTFail("The operation should not fail - NSError: \(String(describing: error))")
                }
            }
        }
    }
    
    func testEditing() {
        self.createScenarioForBobAndAlice { bobSession, aliceSession, bobRoom, aliceRoom, pollStartEvent, expectation in
            self.pollAggregator = PollAggregator(session: bobSession, room: bobRoom, pollStartEventId: pollStartEvent.eventId)
            
            self.delegate = PollAggregatorBlockWrapper(dataUpdateCallback: { aggregator in
                defer {
                    self.isFirstDelegateUpdate = false
                }
                guard self.isFirstDelegateUpdate else {
                    return
                }
                XCTAssertEqual(aggregator.poll?.text, "Some other question")
                XCTAssertEqual(aggregator.poll?.answerOptions.count, 2)
                XCTAssertEqual(aggregator.poll?.hasBeenEdited, true)
                expectation.fulfill()
            })
            
            let oldContent = MXEventContentPollStart(fromJSON: pollStartEvent.content)!
            let newContent = MXEventContentPollStart(question: "Some other question",
                                                     kind: oldContent.kind,
                                                     maxSelections: oldContent.maxSelections,
                                                     answerOptions: oldContent.answerOptions)
            
            
            bobRoom.sendPollUpdate(for: pollStartEvent, oldContent: oldContent, newContent: newContent, localEcho: nil) { result in
                self.pollAggregator.delegate = self.delegate
            } failure: { error in
                XCTFail("The operation should not fail - NSError: \(String(describing: error))")
            }
        }
    }
    
    // MARK: - Private
    
    func createScenarioForBobAndAlice(_ readyToTest: @escaping (MXSession, MXSession, MXRoom, MXRoom, MXEvent, XCTestExpectation) -> Void) {
        
        self.matrixSDKTestsData.doTestWithAliceAndBob(inARoom: self, aliceStore: MXMemoryStore(), bobStore: MXMemoryStore()) { aliceSession, bobSession, roomId, expectation in
            
            let bobRoom = bobSession?.room(withRoomId: roomId)
            
            let answerOptions = [MXEventContentPollStartAnswerOption(uuid: "1", text: "First answer"),
                                 MXEventContentPollStartAnswerOption(uuid: "2", text: "Second answer")]
            
            let pollStartContent = MXEventContentPollStart(question: "Question", kind: kMXMessageContentKeyExtensiblePollKindDisclosed, maxSelections: 100, answerOptions: answerOptions)
            
            bobRoom?.sendPollStart(withContent: pollStartContent, threadId:nil, localEcho: nil, success: { pollStartEventId in
                guard let pollStartEventId = pollStartEventId else {
                    XCTFail("The operation should not fail - Poll start event cannot be sent")
                    expectation?.fulfill()
                    return
                }
                bobSession?.event(withEventId: pollStartEventId, inRoom: roomId, { response in
                    switch response {
                    case .success(let pollStartEvent):
                        let aliceRoom = aliceSession?.room(withRoomId: roomId)
                        aliceRoom?.sendPollResponse(for: pollStartEvent, withAnswerIdentifiers: [pollStartContent.answerOptions.first!.uuid], threadId:nil, localEcho: nil, success: { _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                readyToTest(bobSession!, aliceSession!, bobRoom!, aliceRoom!, pollStartEvent, expectation!)
                            }
                        }, failure: { error in
                            XCTFail("The operation should not fail - NSError: \(String(describing: error))")
                            expectation?.fulfill()
                        })
                    case .failure(let error):
                        XCTFail("The operation should not fail - NSError: \(String(describing: error))")
                        expectation?.fulfill()
                    }
                })
            }, failure: { error in
                XCTFail("The operation should not fail - NSError: \(String(describing: error))")
                expectation?.fulfill()
            })
        }
    }
}

private class PollAggregatorBlockWrapper: PollAggregatorDelegate {
    let dataUpdateCallback: (PollAggregator) -> (Void)
    
    internal init(dataUpdateCallback: @escaping (PollAggregator) -> (Void)) {
        self.dataUpdateCallback = dataUpdateCallback
    }
    
    func pollAggregatorDidStartLoading(_ aggregator: PollAggregator) {
        
    }
    
    func pollAggregatorDidEndLoading(_ aggregator: PollAggregator) {
        
    }
    
    func pollAggregator(_ aggregator: PollAggregator, didFailWithError: Error) {
    
    }
    
    func pollAggregatorDidUpdateData(_ aggregator: PollAggregator) {
        dataUpdateCallback(aggregator)
    }
}

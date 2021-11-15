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
    
    override func setUp() {
        matrixSDKTestsData = MatrixSDKTestsData()
        matrixSDKTestsE2EData = MatrixSDKTestsE2EData(matrixSDKTestsData: matrixSDKTestsData)
    }
    
    override func tearDown() {
        matrixSDKTestsData = nil
        matrixSDKTestsE2EData = nil
    }
        
    func testAggregations() {
        self.createScenarioForBobAndAlice { bobSession, aliceSession, bobRoom, aliceRoom, pollStartEvent, expectation in
            self.pollAggregator = try! PollAggregator(session: bobSession, room: bobRoom, pollStartEvent: pollStartEvent)
            
            let dispatchGroup = DispatchGroup()
            
            for _ in 1...5 {
                dispatchGroup.enter()
                bobRoom.sendPollResponse(for: pollStartEvent, withAnswerIdentifiers: ["2"], localEcho: nil) { _ in
                    dispatchGroup.leave()
                } failure: { error in
                    XCTFail("The operation should not fail - NSError: \(String(describing: error))")
                }
            }
            
            dispatchGroup.enter()
            bobRoom.sendPollResponse(for: pollStartEvent, withAnswerIdentifiers: ["1"], localEcho: nil) { _ in
                dispatchGroup.leave()
            } failure: { error in
                XCTFail("The operation should not fail - NSError: \(String(describing: error))")
            }
            
            dispatchGroup.notify(queue: .main) {
                self.pollAggregator.delegate = PollAggregatorBlockWrapper(dataUpdateCallback: {
                    XCTAssertEqual(self.pollAggregator.poll.answerOptions.first!.count, 2)
                    XCTAssertEqual(self.pollAggregator.poll.answerOptions.last!.count, 0)
                    
                    expectation.fulfill()
                })
            }
        }
    }
    
    func testSessionPausing() {
        self.createScenarioForBobAndAlice { bobSession, aliceSession, bobRoom, aliceRoom, pollStartEvent, expectation in
            self.pollAggregator = try! PollAggregator(session: bobSession, room: bobRoom, pollStartEvent: pollStartEvent)
            
            XCTAssertEqual(self.pollAggregator.poll.answerOptions.first!.count, 1) // One from Alice
            XCTAssertEqual(self.pollAggregator.poll.answerOptions.last!.count, 0)
            
            bobSession.pause()
            
            self.pollAggregator.delegate = PollAggregatorBlockWrapper(dataUpdateCallback: {
                XCTAssertEqual(self.pollAggregator.poll.answerOptions.first!.count, 2)
                XCTAssertEqual(self.pollAggregator.poll.answerOptions.last!.count, 0)
            })
            
            bobRoom.sendPollResponse(for: pollStartEvent, withAnswerIdentifiers: ["1"], localEcho: nil) { _ in
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
            self.pollAggregator = try! PollAggregator(session: bobSession, room: bobRoom, pollStartEvent: pollStartEvent)
            
            XCTAssertEqual(self.pollAggregator.poll.answerOptions.first!.count, 1) // One from Alice
            XCTAssertEqual(self.pollAggregator.poll.answerOptions.last!.count, 0)
            
            bobSession.pause()
            
            self.matrixSDKTestsData.for(bobSession.matrixRestClient, andRoom: bobRoom.roomId, sendMessages: 50, testCase: self) {
                bobRoom.sendPollResponse(for: pollStartEvent, withAnswerIdentifiers: ["1"], localEcho: nil) { _ in
                    aliceRoom.sendPollResponse(for: pollStartEvent, withAnswerIdentifiers: ["1", "2"], localEcho: nil) { _ in
                        self.matrixSDKTestsData.for(aliceSession.matrixRestClient, andRoom: aliceRoom.roomId, sendMessages: 50, testCase: self) {
                            
                            self.pollAggregator.delegate = PollAggregatorBlockWrapper(dataUpdateCallback: {
                                XCTAssertEqual(self.pollAggregator.poll.answerOptions.first!.count, 2) // One from Bob and one from Alice
                                XCTAssertEqual(self.pollAggregator.poll.answerOptions.last!.count, 1) // One from Alice
                                expectation.fulfill()
                            })
                            
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
    
    // MARK: - Private
    
    func createScenarioForBobAndAlice(_ readyToTest: @escaping (MXSession, MXSession, MXRoom, MXRoom, MXEvent, XCTestExpectation) -> Void) {
        
        self.matrixSDKTestsData.doTestWithAliceAndBob(inARoom: self, aliceStore: MXMemoryStore(), bobStore: MXMemoryStore()) { aliceSession, bobSession, roomId, expectation in
            
            let bobRoom = bobSession?.room(withRoomId: roomId)
            
            let answerOptions = [MXEventContentPollStartAnswerOption(uuid: "1", text: "First answer"),
                                 MXEventContentPollStartAnswerOption(uuid: "2", text: "Second answer")]
            
            let pollStartContent = MXEventContentPollStart(question: "Question", kind: kMXMessageContentKeyExtensiblePollKindDisclosed, maxSelections: 100, answerOptions: answerOptions)
            
            bobRoom?.sendPollStart(withContent: pollStartContent, localEcho: nil, success: { pollStartEventId in
                bobSession?.event(withEventId: pollStartEventId, inRoom: roomId, success: { pollStartEvent in
                    let aliceRoom = aliceSession?.room(withRoomId: roomId)
                    aliceRoom?.sendPollResponse(for: pollStartEvent, withAnswerIdentifiers: [pollStartContent.answerOptions.first!.uuid], localEcho: nil, success: { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            readyToTest(bobSession!, aliceSession!, bobRoom!, aliceRoom!, pollStartEvent!, expectation!)
                        }
                    }, failure: { error in
                        XCTFail("The operation should not fail - NSError: \(String(describing: error))")
                        expectation?.fulfill()
                    })
                    
                }, failure: {  error in
                    XCTFail("The operation should not fail - NSError: \(String(describing: error))")
                    expectation?.fulfill()
                })
            }, failure: { error in
                XCTFail("The operation should not fail - NSError: \(String(describing: error))")
                expectation?.fulfill()
            })
        }
    }
}

private class PollAggregatorBlockWrapper: PollAggregatorDelegate {
    
    let dataUpdateCallback: ()->(Void)
    
    internal init(dataUpdateCallback: @escaping () -> (Void)) {
        self.dataUpdateCallback = dataUpdateCallback
    }
    
    func pollAggregatorDidStartLoading(_ aggregator: PollAggregator) {
        
    }
    
    func pollAggregatorDidEndLoading(_ aggregator: PollAggregator) {
        
    }
    
    func pollAggregator(_ aggregator: PollAggregator, didFailWithError: Error) {
    
    }
    
    func pollAggregatorDidUpdateData(_ aggregator: PollAggregator) {
        dataUpdateCallback()
    }
}

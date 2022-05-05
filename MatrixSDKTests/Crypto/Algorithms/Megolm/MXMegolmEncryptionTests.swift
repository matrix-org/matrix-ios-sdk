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
@testable import MatrixSDK

class MXMegolmEncryptionTests: XCTestCase {
    struct SessionIds: Equatable {
        let inbound: [String]
        let outbound: [String]
    }
    
    private var data: MatrixSDKTestsData!
    private var e2eData: MatrixSDKTestsE2EData!
    override func setUp() {
        super.setUp()
        
        data = MatrixSDKTestsData()
        e2eData = MatrixSDKTestsE2EData(matrixSDKTestsData: data)
    }
    
    private func storedSessionIds(in session: MXSession!) -> SessionIds {
        let store = MXRealmCryptoStore(credentials: session.matrixRestClient!.credentials)
        return SessionIds(
            inbound: store!.inboundGroupSessions().map {
                $0.session.sessionIdentifier()
            },
            outbound: store!.outboundGroupSessions().map {
                $0.sessionId
            }
        )
    }
    
    private func isSharedHistoryInLastSession(for session: MXSession!) -> Bool {
        let store = MXRealmCryptoStore(credentials: session.matrixRestClient!.credentials)
        return store?.inboundGroupSessions().last?.sharedHistory == true
    }
    
    func testResetsSessionIfRoomVisibilityChanges() {
        
        // The following tests that oubound session Id (and therefore the related inbound session Id)
        // is reset whenever the room's history visibility changes from shared to not shared.
        e2eData.doE2ETestWithAlice(inARoom: self) { session, roomId, expectation in
            
            let room = session?.room(withRoomId: roomId)
            
            // 1st set of messages
            room?.sendTextMessages(messages: ["Hi", "Hello"]) { _ in
                
                // After first few messages we only expect one inbound and one outbound session
                let sessionIds1 = self.storedSessionIds(in: session)
                XCTAssertEqual(sessionIds1.outbound.count, 1)
                XCTAssertEqual(sessionIds1.inbound.count, 1)
                XCTAssertEqual(sessionIds1.inbound, sessionIds1.outbound)
                XCTAssertTrue(self.isSharedHistoryInLastSession(for: session))
                
                // 2nd set of messages
                room?.sendTextMessages(messages: ["Hi", "Hello"]) { _ in
                    
                    // After second batch of messages nothing has changed that would require resetting
                    // of sessions, therefore sessionIds are unchanged
                    let sessionIds2 = self.storedSessionIds(in: session)
                    XCTAssertEqual(sessionIds2, sessionIds1)
                    XCTAssertTrue(self.isSharedHistoryInLastSession(for: session))
                    
                    // Changing room visibility from shared by default to more restrictive will reset session keys
                    room?.setHistoryVisibility(.joined) { _ in
                        
                        // 3rd set of messages
                        room?.sendTextMessages(messages: ["Hi", "Hello"]) { _ in
                            
                            // Whilst there is still only one onbound session, its identifier has now changed,
                            // and inbound sessions have incremented
                            let sessionIds3 = self.storedSessionIds(in: session)
                            XCTAssertEqual(sessionIds3.outbound.count, 1)
                            XCTAssertNotEqual(sessionIds3.outbound, sessionIds2.outbound)
                            XCTAssertEqual(sessionIds3.inbound.count, 2)
                            XCTAssertEqual(sessionIds3.inbound, sessionIds1.outbound + sessionIds3.outbound)
                            XCTAssertFalse(self.isSharedHistoryInLastSession(for: session))
                            
                            // 4th set of messages
                            room?.sendTextMessages(messages: ["Hi", "Hello"]) { _ in
                                // After fourth batch of messages nothing has changed that would require resetting
                                // of sessions, therefore sessionIds are unchanged
                                let sessionIds4 = self.storedSessionIds(in: session)
                                XCTAssertEqual(sessionIds4, sessionIds3)
                                XCTAssertFalse(self.isSharedHistoryInLastSession(for: session))
                                
                                // Final visibility change back to shared will reset sessions once again
                                room?.setHistoryVisibility(.worldReadable) { _ in
                                    room?.sendTextMessages(messages: ["Hi", "Hello"]) { _ in
                                        
                                        // Still only one outbound session with new ID, and three inbound sessions
                                        let sessionIds5 = self.storedSessionIds(in: session)
                                        XCTAssertEqual(sessionIds5.outbound.count, 1)
                                        XCTAssertNotEqual(sessionIds5.outbound, sessionIds4.outbound)
                                        XCTAssertEqual(sessionIds5.inbound.count, 3)
                                        XCTAssertEqual(sessionIds5.inbound, sessionIds1.outbound + sessionIds3.outbound + sessionIds5.outbound)
                                        XCTAssertTrue(self.isSharedHistoryInLastSession(for: session))
                                    
                                        session?.close()
                                        expectation?.fulfill()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

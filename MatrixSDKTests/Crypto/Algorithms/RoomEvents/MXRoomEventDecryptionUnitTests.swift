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

#if DEBUG

import MatrixSDKCrypto

class MXRoomEventDecryptionUnitTests: XCTestCase {
    class DecryptorStub: CryptoIdentityStub, MXCryptoRoomEventDecrypting {
        enum Error: Swift.Error {
            case cannotDecrypt
        }
        
        var stubbedEvents = [String: DecryptedEvent]()
        func decryptRoomEvent(_ event: MXEvent) throws -> DecryptedEvent {
            guard let decrypted = stubbedEvents[event.eventId] else {
                throw Error.cannotDecrypt
            }
            return decrypted
        }
        
        func requestRoomKey(event: MXEvent) async throws {
        }
    }
    
    var decryptor: DecryptorStub!
    var roomDecryptor: MXRoomEventDecryption!
    
    override func setUp() {
        decryptor = DecryptorStub()
        roomDecryptor = MXRoomEventDecryption(handler: decryptor)
    }
    
    // MARK: - Decrypt
    
    func test_decrypt_returnsDecryptionResults() async {
        let plain = [
            "text": "hello"
        ]
        let event = MXEvent.encryptedFixture(
            id: "1",
            sessionId: "123"
        )
        decryptor.stubbedEvents = [
            "1": .stub(clearEvent: plain)
        ]
        
        let results = await roomDecryptor.decrypt(events: [event])
        
        XCTAssertEqual(results.first?.clearEvent as? [String: String], plain)
    }
    
    func test_decrypt_returnsDecryptedAndErrorResults() async {
        let plain = [
            "text": "hello"
        ]
        let events: [MXEvent] = [
            .encryptedFixture(
                id: "1",
                sessionId: "123"
            ),
            .encryptedFixture(
                id: "2",
                sessionId: "456"
            ),
            .encryptedFixture(
                id: "3",
                sessionId: "123"
            )
        ]
        
        decryptor.stubbedEvents = [
            "2": .stub(clearEvent: plain)
        ]
        
        let results = await roomDecryptor.decrypt(events: events)
        
        XCTAssertEqual(results.count, 3)
        XCTAssertNotNil(results[0].error)
        XCTAssertEqual(results[1].clearEvent as? [String: String], plain)
        XCTAssertNotNil(results[2].error)
    }
    
    // MARK: - Room key
    
    func test_handlePossibleRoomKeyEvent_doesNothingIfInvalidRoomKeyEvent() async {
        let events = await prepareEventsForRedecryption()
        let invalidEvent = MXEvent.fixture(id: 123)
        
        await roomDecryptor.handlePossibleRoomKeyEvent(invalidEvent)
        await waitForDecryption()
        
        XCTAssertNil(events[0].clear)
        XCTAssertNil(events[1].clear)
        XCTAssertNil(events[2].clear)
    }
    
    func test_handlePossibleRoomKeyEvent_decryptsMatchingEventsOnRoomKey() async {
        let events = await prepareEventsForRedecryption()
        let roomKey = MXEvent.roomKeyFixture(sessionId: "123")
        
        await roomDecryptor.handlePossibleRoomKeyEvent(roomKey)
        await waitForDecryption()

        XCTAssertNotNil(events[0].clear)
        XCTAssertNil(events[1].clear)
        XCTAssertNotNil(events[2].clear)
    }
    
    func test_handlePossibleRoomKeyEvent_decryptsMatchingEventsOnForwardedRoomKey() async {
        let events = await prepareEventsForRedecryption()
        let roomKey = MXEvent.forwardedRoomKeyFixture(sessionId: "123")
        
        await roomDecryptor.handlePossibleRoomKeyEvent(roomKey)
        await waitForDecryption()

        XCTAssertNotNil(events[0].clear)
        XCTAssertNil(events[1].clear)
        XCTAssertNotNil(events[2].clear)
    }
    
    // MARK: - Retry all
    
    func test_retryUndecryptedEvents() async {
        let events = await prepareEventsForRedecryption()
        
        await roomDecryptor.retryUndecryptedEvents(sessionIds: ["123", "456"])
        await waitForDecryption()
        
        XCTAssertNotNil(events[0].clear)
        XCTAssertNotNil(events[1].clear)
        XCTAssertNotNil(events[2].clear)
    }
    
    // MARK: - Helpers
    
    private func prepareEventsForRedecryption() async -> [MXEvent] {
        // We assume two sessions, only one of which will later recieve a key
        let session1 = "123"
        let session2 = "456"
        
        // Prepare three events, encrypted with either of the two sessions
        let events: [MXEvent] = [
            .encryptedFixture(
                id: "1",
                sessionId: session1
            ),
            .encryptedFixture(
                id: "2",
                sessionId: session2
            ),
            .encryptedFixture(
                id: "3",
                sessionId: session1
            )
        ]
        
        // Attempt to decrypt these events, which will produce errors
        // and add them to an internal undecrypted events cache
        let results = await roomDecryptor.decrypt(events: events)
        for (event, result) in zip(events, results) {
            event.setClearData(result)
        }
        
        // Now stub out decryption result so that if these events are decrypted again
        // we get the correct result
        let decrypted = DecryptedEvent.stub(clearEvent: ["type": "m.decrypted"])
        decryptor.stubbedEvents = [
            "1": decrypted,
            "2": decrypted,
            "3": decrypted
        ]
        
        return events
    }
    
    private func waitForDecryption() async {
        // When decrypting successfully, a notification will be triggered on the main thread, so we have to
        // make sure we wait until this happens. We cannot listen to notifications directly, because
        // repeated decryption failures will not trigger any. Instead simply wait a little while.
        try! await Task.sleep(nanoseconds: 1_000_000)
    }
}

#endif

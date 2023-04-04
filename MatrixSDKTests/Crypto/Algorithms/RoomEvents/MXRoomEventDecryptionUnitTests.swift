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
    
    var handler: DecryptorStub!
    var decryptor: MXRoomEventDecryption!
    
    override func setUp() {
        handler = DecryptorStub()
        decryptor = MXRoomEventDecryption(handler: handler)
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
        handler.stubbedEvents = [
            "1": .stub(clearEvent: plain)
        ]
        
        let results = await decryptor.decrypt(events: [event])
        
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
        
        handler.stubbedEvents = [
            "2": .stub(clearEvent: plain)
        ]
        
        let results = await decryptor.decrypt(events: events)
        
        XCTAssertEqual(results.count, 3)
        XCTAssertNotNil(results[0].error)
        XCTAssertEqual(results[1].clearEvent as? [String: String], plain)
        XCTAssertNotNil(results[2].error)
    }
    
    // MARK: - Room key
    
    func test_handlePossibleRoomKeyEvent_doesNothingIfInvalidRoomKeyEvent() async {
        let events = await prepareEventsForRedecryption()
        let invalidEvent = MXEvent.fixture(id: 123)
        
        await decryptor.handlePossibleRoomKeyEvent(invalidEvent)
        // We do not expect anything to be decrypted, so there is no notification or other signal to listen to
        // We will simply wait an entire second and assert nothing was decrypted
        try! await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertNil(events[0].clear)
        XCTAssertNil(events[1].clear)
        XCTAssertNil(events[2].clear)
    }
    
    func test_handlePossibleRoomKeyEvent_decryptsMatchingEventsOnRoomKey() async {
        let events = await prepareEventsForRedecryption()
        let roomKey = MXEvent.roomKeyFixture(sessionId: "123")
        
        await decryptor.handlePossibleRoomKeyEvent(roomKey)
        await waitForDecryption(events: events)

        XCTAssertNotNil(events[0].clear)
        XCTAssertNil(events[1].clear)
        XCTAssertNotNil(events[2].clear)
    }
    
    func test_handlePossibleRoomKeyEvent_decryptsMatchingEventsOnForwardedRoomKey() async {
        let events = await prepareEventsForRedecryption()
        let roomKey = MXEvent.forwardedRoomKeyFixture(sessionId: "123")
        
        await decryptor.handlePossibleRoomKeyEvent(roomKey)
        await waitForDecryption(events: events)

        XCTAssertNotNil(events[0].clear)
        XCTAssertNil(events[1].clear)
        XCTAssertNotNil(events[2].clear)
    }
    
    // MARK: - Retry all
    
    func test_retryUndecryptedEvents() async {
        let events = await prepareEventsForRedecryption()
        
        await decryptor.retryUndecryptedEvents(sessionIds: ["123", "456"])
        await waitForDecryption(events: events)
        
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
        let results = await decryptor.decrypt(events: events)
        for (event, result) in zip(events, results) {
            event.setClearData(result)
        }
        
        // Now stub out decryption result so that if these events are decrypted again
        // we get the correct result
        let decrypted = DecryptedEvent.stub(clearEvent: ["type": "m.decrypted"])
        handler.stubbedEvents = [
            "1": decrypted,
            "2": decrypted,
            "3": decrypted
        ]
        
        return events
    }
    
    private func waitForDecryption(events: [MXEvent]) async {
        // When decrypting successfully, a notification will be triggered on the main thread, so we have to
        // make sure we wait until this happens. We cannot listen to notifications directly, because
        // repeated decryption failures will not trigger any. Instead simply wait a little while.
        
        // Maximum 100 attempts each pausing for a tenth of a second
        for _ in 0 ..< 100 {
            
            // As soon as at least one event is decrypted, we assume all are and return
            if events.contains(where: { $0.clear != nil }) {
                return
            }
            
            // Otherwise wait for a 0.1 second and run the next loop cycle
            try! await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}

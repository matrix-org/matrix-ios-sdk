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
import XCTest
@testable import MatrixSDK

class MXRoomKeyInfoFactoryUnitTests: XCTestCase {
    
    var store: MXMemoryCryptoStore!
    var factory: MXRoomKeyInfoFactory!
    override func setUp() {
        store = MXMemoryCryptoStore(credentials: MXCredentials(homeServer: "", userId: "Alice", accessToken: nil))
        factory = MXRoomKeyInfoFactory(myUserId: "Alice", store: store)
        storeOutgoingKeyRequest(requestId: "1")
    }
    
    // MARK: - Any event
    
    func test_roomKeyInfo_isNilForInvalidEvent() {
        let info = factory.roomKey(for: MXEvent(fromJSON: [:]))
        XCTAssertNil(info)
    }
    
    // MARK: - Room key event
    
    func test_roomKeyInfo_createFromRoomKeyEvent() {
        let event = MXEvent.roomKeyFixture()
        
        let key = factory.roomKey(for: event)
        
        let info = key?.info
        XCTAssertNotNil(key)
        XCTAssertEqual(key?.type, .safe)
        XCTAssertEqual(info?.algorithm, "megolm")
        XCTAssertEqual(info?.sessionId, "session1")
        XCTAssertEqual(info?.sessionKey, "<key>")
        XCTAssertEqual(info?.roomId, "!123:matrix.org")
        XCTAssertEqual(info?.senderKey, "<sender_key>")
        XCTAssertNil(info?.forwardingKeyChain)
        XCTAssertEqual(info?.keysClaimed as? NSDictionary, ["ed25519": "<claimed_key>"])
        XCTAssertEqual(info?.exportFormat, false)
        XCTAssertEqual(info?.sharedHistory, false)
    }
    
    // MARK: - Forwarded room key event
    
    func test_roomKeyInfo_isUnrequestedIfKeyNotRequested() {
        store.deleteOutgoingRoomKeyRequest(withRequestId: "1")
        storeDevice(userId: "Alice", trusted: true, identityKey: "AliceSender")
        let event = MXEvent.forwardedRoomKeyFixture(
            senderKey: "AliceSender"
        )
        
        let key = factory.roomKey(for: event)
        
        let info = key?.info
        XCTAssertNotNil(key)
        XCTAssertEqual(key?.type, .unrequested)
        XCTAssertEqual(info?.algorithm, "megolm")
        XCTAssertEqual(info?.sessionId, "session1")
        XCTAssertEqual(info?.sessionKey, "<key>")
        XCTAssertEqual(info?.roomId, "!123:matrix.org")
        XCTAssertEqual(info?.senderKey, "<initial_sender_key>")
        XCTAssertEqual(info?.forwardingKeyChain, ["AliceSender"])
        XCTAssertEqual(info?.keysClaimed as? NSDictionary, ["ed25519": "<claimed_key>"])
        XCTAssertEqual(info?.exportFormat, true)
        XCTAssertEqual(info?.sharedHistory, false)
    }
    
    func test_roomKeyInfo_isUnsafeIfNotFromMyself() {
        storeDevice(userId: "Bob", trusted: true, identityKey: "AliceSender")
        let event = MXEvent.forwardedRoomKeyFixture(
            senderKey: "AliceSender"
        )
        
        let key = factory.roomKey(for: event)
        
        let info = key?.info
        XCTAssertNotNil(key)
        XCTAssertEqual(key?.type, .unsafe)
        XCTAssertEqual(info?.algorithm, "megolm")
        XCTAssertEqual(info?.sessionId, "session1")
        XCTAssertEqual(info?.sessionKey, "<key>")
        XCTAssertEqual(info?.roomId, "!123:matrix.org")
        XCTAssertEqual(info?.senderKey, "<initial_sender_key>")
        XCTAssertEqual(info?.forwardingKeyChain, ["AliceSender"])
        XCTAssertEqual(info?.keysClaimed as? NSDictionary, ["ed25519": "<claimed_key>"])
        XCTAssertEqual(info?.exportFormat, true)
        XCTAssertEqual(info?.sharedHistory, false)
    }
    
    func test_roomKeyInfo_isUnsafeIfFromUnverifiedDevice() {
        storeDevice(userId: "Alice", trusted: false, identityKey: "AliceSender")
        let event = MXEvent.forwardedRoomKeyFixture(
            senderKey: "AliceSender"
        )
        
        let key = factory.roomKey(for: event)
        
        let info = key?.info
        XCTAssertNotNil(key)
        XCTAssertEqual(key?.type, .unsafe)
        XCTAssertEqual(info?.algorithm, "megolm")
        XCTAssertEqual(info?.sessionId, "session1")
        XCTAssertEqual(info?.sessionKey, "<key>")
        XCTAssertEqual(info?.roomId, "!123:matrix.org")
        XCTAssertEqual(info?.senderKey, "<initial_sender_key>")
        XCTAssertEqual(info?.forwardingKeyChain, ["AliceSender"])
        XCTAssertEqual(info?.keysClaimed as? NSDictionary, ["ed25519": "<claimed_key>"])
        XCTAssertEqual(info?.exportFormat, true)
        XCTAssertEqual(info?.sharedHistory, false)
    }
    
    func test_roomKeyInfo_createFromForwardedRoomKeyEvent() {
        storeDevice(userId: "Alice", trusted: true, identityKey: "AliceSender")
        let event = MXEvent.forwardedRoomKeyFixture(
            senderKey: "AliceSender"
        )
        
        let key = factory.roomKey(for: event)
        
        let info = key?.info
        XCTAssertNotNil(key)
        XCTAssertEqual(key?.type, .safe)
        XCTAssertEqual(info?.algorithm, "megolm")
        XCTAssertEqual(info?.sessionId, "session1")
        XCTAssertEqual(info?.sessionKey, "<key>")
        XCTAssertEqual(info?.roomId, "!123:matrix.org")
        XCTAssertEqual(info?.senderKey, "<initial_sender_key>")
        XCTAssertEqual(info?.forwardingKeyChain, ["AliceSender"])
        XCTAssertEqual(info?.keysClaimed as? NSDictionary, ["ed25519": "<claimed_key>"])
        XCTAssertEqual(info?.exportFormat, true)
        XCTAssertEqual(info?.sharedHistory, false)
    }
    
    // MARK: - Helpers
    
    func storeOutgoingKeyRequest(
        requestId: String = "1",
        algorithm: String = "megolm",
        roomId: String = "!123:matrix.org",
        sessionId: String = "session1",
        senderKey: String = "<initial_sender_key>"
    ) {
        let request = MXOutgoingRoomKeyRequest()
        request.requestId = requestId
        
        request.requestBody = [
            "room_id": roomId,
            "algorithm": algorithm,
            "sender_key": senderKey,
            "session_id": sessionId
        ]
        store.store(request)
    }
    
    func storeDevice(userId: String, trusted: Bool, identityKey: String) {
        let trust = MXDeviceTrustLevel(
            localVerificationStatus: trusted ? .verified : .unverified,
            crossSigningVerified: false
        )
        let device = MXDeviceInfo(fromJSON: [
            "user_id": userId,
            "device_id": "ABC",
            "keys": ["curve25519:ABC": identityKey]
        ])!
        device.setValue(trust, forKey: "trustLevel")
        store.storeDevice(forUser: userId, device: device)
    }
}

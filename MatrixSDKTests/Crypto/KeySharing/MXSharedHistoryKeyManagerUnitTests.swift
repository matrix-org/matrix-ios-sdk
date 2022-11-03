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

class MXSharedHistoryKeyManagerUnitTests: XCTestCase {
    class CryptoStub: MXLegacyCrypto {
        var devices = MXUsersDevicesMap<MXDeviceInfo>()
        
        override func downloadKeys(_ userIds: [String], forceDownload: Bool, success: ((MXUsersDevicesMap<MXDeviceInfo>, [String : MXCrossSigningInfo]) -> Void)?, failure: ((Error) -> Void)? = nil) -> MXHTTPOperation? {
            success?(devices, [:])
            return MXHTTPOperation()
        }
    }
    
    class SpyService: NSObject, MXSharedHistoryKeyService {
        struct SessionStub: Hashable {
            let roomId: String
            let sessionId: String
            let senderKey: String
        }
        
        var sharedHistory: Set<SessionStub>?
        func hasSharedHistory(forRoomId roomId: String!, sessionId: String!, senderKey: String!) -> Bool {
            guard let sharedHistory = sharedHistory else {
                return true
            }
            
            let session = SessionStub(roomId: roomId, sessionId: sessionId, senderKey: senderKey)
            return sharedHistory.contains(session)
        }
        
        var requests = [MXSharedHistoryKeyRequest]()
        func shareKeys(for request: MXSharedHistoryKeyRequest!, success: (() -> Void)!, failure: ((Error?) -> Void)!) {
            requests.append(request)
            success?()
        }
    }
    
    class EnumeratorStub: NSObject, MXEventsEnumerator {
        var messages: [MXEvent] = []
        
        func nextEventsBatch(_ eventsCount: UInt, threadId: String!) -> [MXEvent]! {
            return nil
        }
        
        var nextEvent: MXEvent? {
            if messages.isEmpty {
                return nil
            }
            return messages.removeFirst()
        }
        
        var remaining: UInt {
            return UInt(messages.count)
        }
    }
    
    var enumerator: EnumeratorStub!
    var crypto: CryptoStub!
    var service: SpyService!
    var manager: MXSharedHistoryKeyManager!
    
    override func setUp() {
        super.setUp()
        
        enumerator = EnumeratorStub()
        crypto = CryptoStub()
        crypto.devices.setObject(MXDeviceInfo(deviceId: "1"), forUser: "user1", andDevice: "1")
        
        service = SpyService()
    }
    
    private func makeEvent(
        sessionId: String = "123",
        senderKey: String = "456"
    ) -> MXEvent {
        MXEvent(fromJSON: [
            "room_id": "ABC",
            "type": kMXEventTypeStringRoomEncrypted,
            "content": [
                "session_id": sessionId,
                "sender_key": senderKey,
            ]
        ])
    }
    
    private func makeInboundSession(
        roomId: String = "ABC",
        sessionId: String = "123",
        senderKey: String = "456"
    ) -> SpyService.SessionStub {
        return .init(roomId: roomId, sessionId: sessionId, senderKey: senderKey)
    }
    
    private func shareKeys(
        userId: String = "user1",
        roomId: String = "ABC",
        enumerator: MXEventsEnumerator? = nil,
        limit: Int = .max
    ) {
        manager = MXSharedHistoryKeyManager(roomId: roomId, crypto: crypto, service: service)
        manager.shareMessageKeys(
            withUserId: userId,
            messageEnumerator: enumerator ?? self.enumerator,
            limit: limit
        )
    }
    
    func testDoesNotCreateRequestIfNoKnownDevices() {
        enumerator.messages = [
            makeEvent(sessionId: "A", senderKey: "B")
        ]
        crypto.devices = MXUsersDevicesMap<MXDeviceInfo>()
        
        shareKeys()
        
        XCTAssertEqual(service.requests.count, 0)
    }
    
    func testCreateRequestForSingleMessage() {
        enumerator.messages = [
            makeEvent(sessionId: "A", senderKey: "B")
        ]
        crypto.devices.setObject(MXDeviceInfo(deviceId: "1"), forUser: "user1", andDevice: "1")
        crypto.devices.setObject(MXDeviceInfo(deviceId: "2"), forUser: "user1", andDevice: "2")
        crypto.devices.setObject(MXDeviceInfo(deviceId: "3"), forUser: "user2", andDevice: "3")
        
        shareKeys()
        
        XCTAssertEqual(service.requests.count, 1)
        XCTAssertEqual(
            service.requests.first,
            MXSharedHistoryKeyRequest(
                userId: "user1",
                devices: [
                    MXDeviceInfo(deviceId: "1"),
                    MXDeviceInfo(deviceId: "2")
                ],
                roomId: "ABC",
                sessionId: "A",
                senderKey: "B"
            )
        )
    }
    
    func testCreateOneRequestPerSessionIdAndSenderKey() {
        enumerator.messages = [
            makeEvent(sessionId: "1", senderKey: "A"),
            makeEvent(sessionId: "1", senderKey: "B"),
            makeEvent(sessionId: "1", senderKey: "A"),
            makeEvent(sessionId: "2", senderKey: "A"),
            makeEvent(sessionId: "3", senderKey: "A"),
            makeEvent(sessionId: "2", senderKey: "A"),
            makeEvent(sessionId: "3", senderKey: "B"),
        ]
        
        shareKeys()
        
        let identifiers = service.requests.map { [$0.sessionId, $0.senderKey] }
        XCTAssertEqual(service.requests.count, 5)
        XCTAssertTrue(identifiers.contains(["1", "A"]))
        XCTAssertTrue(identifiers.contains(["1", "B"]))
        XCTAssertTrue(identifiers.contains(["2", "A"]))
        XCTAssertTrue(identifiers.contains(["3", "A"]))
        XCTAssertTrue(identifiers.contains(["3", "B"]))
    }
    
    func testCreateRequestsWithinLimit() {
        enumerator.messages = [
            makeEvent(sessionId: "5"),
            makeEvent(sessionId: "4"),
            makeEvent(sessionId: "3"),
            makeEvent(sessionId: "2"),
            makeEvent(sessionId: "1"),
        ]
        
        shareKeys(limit: 3)
        
        let identifiers = service.requests.map { $0.sessionId }
        XCTAssertEqual(service.requests.count, 3)
        XCTAssertEqual(Set(identifiers), ["5", "4", "3"])
    }
    
    func testCreateRequestsOnlyForSessionsWithSharedHistory() {
        enumerator.messages = [
            makeEvent(sessionId: "1"),
            makeEvent(sessionId: "2"),
            makeEvent(sessionId: "3"),
            makeEvent(sessionId: "4"),
            makeEvent(sessionId: "5"),
        ]
        service.sharedHistory = [
            makeInboundSession(sessionId: "1"),
            makeInboundSession(sessionId: "2"),
            makeInboundSession(sessionId: "4"),
        ]
        
        shareKeys()
        
        let identifiers = service.requests.map { $0.sessionId }
        XCTAssertEqual(service.requests.count, 3)
        XCTAssertEqual(Set(identifiers), ["1", "2", "4"])
    }
    
    func testIgnoresEventsWithMismatchedRoomId() {
        enumerator.messages = [
            makeEvent(sessionId: "1"),
            makeEvent(sessionId: "2"),
            makeEvent(sessionId: "3"),
        ]
        service.sharedHistory = [
            makeInboundSession(
                roomId: "XYZ",
                sessionId: "1"
            ),
            makeInboundSession(
                roomId: "ABC",
                sessionId: "2"
            ),
            makeInboundSession(
                roomId: "XYZ",
                sessionId: "3"
            ),
        ]
        
        shareKeys(roomId: "ABC")
        
        XCTAssertEqual(service.requests.count, 1)
        XCTAssertEqual(service.requests.first?.sessionId, "2")
    }
}

extension MXSharedHistoryKeyRequest {
    public override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? MXSharedHistoryKeyRequest else {
            return false
        }
        return object.userId == userId
        && object.devices.map { $0.deviceId } == devices.map { $0.deviceId }
        && object.roomId == roomId
        && object.sessionId == sessionId
        && object.senderKey == senderKey
    }
}

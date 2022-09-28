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

private let BobSenderKey = "BobDeviceCurveKey"

class MXUnrequestedForwardedRoomKeyManagerUnitTests: XCTestCase {
    class Delegate: MXUnrequestedForwardedRoomKeyManagerDelegate {
        var stubbedUserKeys = [String: [MXDeviceInfo]]()
        var spyKeys = [MXRoomKeyInfo]()
        
        func downloadDeviceKeys(userId: String, completion: @escaping (MXUsersDevicesMap<MXDeviceInfo>) -> Void) {
            let map = MXUsersDevicesMap<MXDeviceInfo>()
            for (userId, devices) in stubbedUserKeys {
                for device in devices {
                    map.setObject(device, forUser: userId, andDevice: device.deviceId)
                }
            }
            completion(map)
        }
        
        func acceptRoomKey(keyInfo: MXRoomKeyInfo) {
            spyKeys.append(keyInfo)
        }
    }
    
    class StubDateProvider: MXDateProviding {
        var stubbedDate: Date?
        func currentDate() -> Date {
            return stubbedDate ?? Date()
        }
    }
    
    var dateProvider: StubDateProvider!
    var manager: MXUnrequestedForwardedRoomKeyManager!
    var delegate: Delegate!
    
    override func setUp() {
        dateProvider = StubDateProvider()
        manager = MXUnrequestedForwardedRoomKeyManager(dateProvider: dateProvider)
        delegate = Delegate()
        manager.delegate = delegate
        
        delegate.stubbedUserKeys = [
            "Bob": [
                MXDeviceInfo(fromJSON: [
                    "user_id": "Bob",
                    "device_id": "BobDevice",
                    "keys": [
                        "ed25519:BobDevice": "BobDeviceEdKey",
                        "curve25519:BobDevice": BobSenderKey,
                    ]
                ])
            ]
        ]
    }
    
    func test_processUnrequestedKeys_doesNothingIfNoKeys() {
        manager.processUnrequestedKeys()
        XCTAssertEqual(delegate.spyKeys, [])
    }
    
    func test_processUnrequestedKeys_addsAllKeysForInvitedRooms() {
        let keys = [
            MXRoomKeyInfo.fixture(sessionId: "1", roomId: "A"),
            MXRoomKeyInfo.fixture(sessionId: "2", roomId: "A"),
            MXRoomKeyInfo.fixture(sessionId: "3", roomId: "B"),
            MXRoomKeyInfo.fixture(sessionId: "4", roomId: "C"),
        ]
        for info in keys {
            manager.addPendingKey(keyInfo: info, senderId: "Bob", senderKey: BobSenderKey)
        }
        manager.onRoomInvite(roomId: "A", senderId: "Bob")
        manager.onRoomInvite(roomId: "C", senderId: "Bob")
        
        manager.processUnrequestedKeys()
        
        let sessionIds = delegate.spyKeys.map { $0.sessionId }
        XCTAssertEqual(Set(sessionIds), ["1", "2", "4"])
    }
    
    func test_processUnrequestedKeys_addsOnlyKeysFromRoomInviter() {
        manager.addPendingKey(
            keyInfo: MXRoomKeyInfo.fixture(sessionId: "1", roomId: "A"),
            senderId: "Bob",
            senderKey: "AliceKey"
        )
        manager.addPendingKey(
            keyInfo: MXRoomKeyInfo.fixture(sessionId: "2", roomId: "A"),
            senderId: "Bob",
            senderKey: BobSenderKey
        )
        manager.addPendingKey(
            keyInfo: MXRoomKeyInfo.fixture(sessionId: "3", roomId: "A"),
            senderId: "Bob",
            senderKey: "CharlieKey"
        )
        manager.onRoomInvite(roomId: "A", senderId: "Bob")

        manager.processUnrequestedKeys()

        let sessionIds = delegate.spyKeys.map { $0.sessionId }
        XCTAssertEqual(Set(sessionIds), ["2"])
    }
    
    func test_processUnrequestedKeys_doesNotAddKeysIfSenderNotValid() {
        manager.addPendingKey(
            keyInfo: MXRoomKeyInfo.fixture(sessionId: "2", roomId: "A"),
            senderId: "Bob",
            senderKey: "BobInvalidKey"
        )
        manager.onRoomInvite(roomId: "A", senderId: "Bob")

        manager.processUnrequestedKeys()

        XCTAssertEqual(delegate.spyKeys, [])
    }
    
    func test_processUnrequestedKeys_removesProcessedKeys() {
        delegate.spyKeys = []
        manager.addPendingKey(
            keyInfo: MXRoomKeyInfo.fixture(sessionId: "1", roomId: "A"),
            senderId: "Bob",
            senderKey: BobSenderKey
        )
        manager.processUnrequestedKeys()
        XCTAssertEqual(delegate.spyKeys.count, 0)
        
        delegate.spyKeys = []
        manager.onRoomInvite(roomId: "A", senderId: "Bob")
        manager.processUnrequestedKeys()
        XCTAssertEqual(delegate.spyKeys.count, 1)
        
        delegate.spyKeys = []
        manager.processUnrequestedKeys()
        XCTAssertEqual(delegate.spyKeys.count, 0)
    }
    
    func test_processUnrequestedKeys_removesInvitesMoreThan10MinutesFromPresent() {
        let minutesToRoom: [TimeInterval: String] = [
            -10: "A",
             -9: "B",
             0: "C",
             9: "D",
             10: "E"
        ]
        
        // First add all the keys
        for (minutes, roomId) in minutesToRoom {
            stubDate(timeInterval: minutes * 60)
            manager.addPendingKey(
                keyInfo: MXRoomKeyInfo.fixture(sessionId: roomId, roomId: roomId),
                senderId: "Bob",
                senderKey: BobSenderKey
            )
        }
        
        // Now add invites
        for (minutes, roomId) in minutesToRoom {
            stubDate(timeInterval: minutes * 60)
            manager.onRoomInvite(roomId: roomId, senderId: "Bob")
        }
        
        // Set the date to present
        stubDate(timeInterval: 0)
        
        // Process invites
        manager.processUnrequestedKeys()
        
        let sessionIds = delegate.spyKeys.map { $0.sessionId }
        XCTAssertEqual(Set(sessionIds), ["B", "C", "D"])
    }
    
    func test_processUnrequestedKeys_removesKeysOlderThan10MinutesOfInvite() {
        stubDate(timeInterval: 0)
        manager.addPendingKey(
            keyInfo: MXRoomKeyInfo.fixture(sessionId: "1", roomId: "A"),
            senderId: "Bob",
            senderKey: BobSenderKey
        )
        stubDate(timeInterval: 1 * 60)
        manager.addPendingKey(
            keyInfo: MXRoomKeyInfo.fixture(sessionId: "2", roomId: "A"),
            senderId: "Bob",
            senderKey: BobSenderKey
        )
        stubDate(timeInterval: 10 * 60)
        manager.onRoomInvite(roomId: "A", senderId: "Bob")
        stubDate(timeInterval: 19 * 60)
        
        manager.processUnrequestedKeys()
        
        XCTAssertEqual(delegate.spyKeys.count, 1)
        XCTAssertEqual(delegate.spyKeys.first?.sessionId, "2")
    }
    
    // MARK: - Helpers
    
    func stubDate(timeInterval: TimeInterval) {
        dateProvider.stubbedDate = Date(timeIntervalSince1970: timeInterval)
    }
}

private extension MXRoomKeyInfo {
    static func fixture(
        sessionId: String,
        roomId: String
    ) -> MXRoomKeyInfo {
        return MXRoomKeyInfo(
            algorithm: "",
            sessionId: sessionId,
            sessionKey: "",
            roomId: roomId,
            senderKey: "",
            forwardingKeyChain: nil,
            keysClaimed: [:],
            exportFormat: false,
            sharedHistory: false
        )
    }
}

// 
// Copyright 2023 The Matrix.org Foundation C.I.C
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

class MXRoomEventEncryptionUnitTests: XCTestCase {
    class StateStub: MXRoomState {
        var stubbedAlgorithm: String? = kMXCryptoMegolmAlgorithm
        override var encryptionAlgorithm: String! {
            return stubbedAlgorithm
        }
        
        var stubbedHistoryVisibility: MXRoomHistoryVisibility?
        override var __historyVisibility: String? {
            return stubbedHistoryVisibility?.identifier
        }
    }
    
    class MembersStub: MXRoomMembers {
        var stubbedMembers: [MemberStub]?
        override var members: [MXRoomMember]! {
            return stubbedMembers
        }
        
        var eligibleUsers = Set<String>()
        override func encryptionTargetMembers(_ historyVisibility: String!) -> [MXRoomMember]! {
            return stubbedMembers?.filter {
                eligibleUsers.contains($0.userId)
            }
        }
    }
    
    class MemberStub: MXRoomMember {
        var stubbedUserId: String?
        override var userId: String! {
            stubbedUserId
        }
        
        init(userId: String) {
            self.stubbedUserId = userId
            super.init()
        }
    }
    
    class RoomStub: MXRoom {
        var isEncrypted: Bool = true
        override var summary: MXRoomSummary! {
            let summary = MXRoomSummary()
            summary.isEncrypted = isEncrypted
            return summary
        }
        
        var stubbedState: StateStub?
        override func state(_ onComplete: ((MXRoomState?) -> Void)!) {
            onComplete(stubbedState)
        }
        
        var stubbedMembers: MembersStub?
        override func members(
            _ success: ((MXRoomMembers?) -> Void)!,
            lazyLoadedMembers: ((MXRoomMembers?) -> Void)!,
            failure: ((Swift.Error?) -> Void)!
        ) -> MXHTTPOperation! {
            success?(stubbedMembers)
            return MXHTTPOperation()
        }
    }
    
    class EncryptorStub: CryptoIdentityStub, MXCryptoRoomEventEncrypting {
        var onlyAllowTrustedDevices: Bool = false
        
        var trackedUsers: Set<String> = []
        func isUserTracked(userId: String) -> Bool {
            return trackedUsers.contains(userId)
        }
        
        func updateTrackedUsers(_ users: [String]) {
            trackedUsers = trackedUsers.union(users)
        }
        
        var stubbedRoomSettings: [String: RoomSettings] = [:]
        func roomSettings(roomId: String) -> RoomSettings? {
            return stubbedRoomSettings[roomId]
        }
        
        func setRoomAlgorithm(roomId: String, algorithm: EventEncryptionAlgorithm) throws {
            stubbedRoomSettings[roomId] = .init(
                algorithm: algorithm,
                onlyAllowTrustedDevices: stubbedRoomSettings[roomId]?.onlyAllowTrustedDevices ?? false
            )
        }
        
        func setOnlyAllowTrustedDevices(for roomId: String, onlyAllowTrustedDevices: Bool) throws {
            stubbedRoomSettings[roomId] = .init(
                algorithm: stubbedRoomSettings[roomId]?.algorithm ?? .megolmV1AesSha2,
                onlyAllowTrustedDevices: onlyAllowTrustedDevices
            )
        }
        
        var sharedUsers = [String]()
        var sharedSettings: EncryptionSettings?
        func shareRoomKeysIfNecessary(roomId: String, users: [String], settings: EncryptionSettings) async throws {
            sharedUsers = users
            sharedSettings = settings
        }
        
        func encryptRoomEvent(content: [AnyHashable: Any], roomId: String, eventType: String) throws -> [String: Any] {
            return [
                // Simulate encryption by moving content to `ciphertext`
                "ciphertext": content
            ]
        }
        
        func discardRoomKey(roomId: String) {
        }
    }
    
    var handler: EncryptorStub!
    var encryptor: MXRoomEventEncryption!
    var roomId = "ABC"
    var room: RoomStub!
    var state: StateStub!
    var members: MembersStub!
    
    override func setUp() {
        handler = EncryptorStub()
        room = .init(roomId: roomId, andMatrixSession: nil)
        state = .init(roomId: roomId, andMatrixSession: nil, andDirection: true)
        members = .init()
        
        room.stubbedState = state
        room.stubbedMembers = members
        
        encryptor = MXRoomEventEncryption(
            handler: handler,
            getRoomAction: { id in
                id == self.room.roomId ? self.room : nil
            }
        )
    }
    
    // MARK: - Is encrypted
    
    func test_isRoomEncrypted() {
        XCTAssertFalse(encryptor.isRoomEncrypted(roomId: roomId))
        
        handler.stubbedRoomSettings[roomId] = .init(
            algorithm: .megolmV1AesSha2,
            onlyAllowTrustedDevices: false
        )
        
        XCTAssertTrue(encryptor.isRoomEncrypted(roomId: roomId))
    }
    
    // MARK: - Ensure keys
    
    func test_ensureRoomKeysShared_throwsForMissingRoom() async {
        do {
            try await encryptor.ensureRoomKeysShared(roomId: "unknown")
            XCTFail("Should not succeed")
        } catch {
            XCTAssertNotNil(error)
        }
    }
    
    func test_ensureRoomKeysShared_skipForUnencryptedRooms() async throws {
        room.isEncrypted = false
        try await encryptor.ensureRoomKeysShared(roomId: roomId)
        XCTAssertNil(handler.sharedSettings)
    }
    
    func test_ensureRoomKeysShared_correctEncryptionAlgorithm() async throws {
        XCTAssertNil(handler.roomSettings(roomId: roomId))
        
        // No algorithm -> throws + nothing stored
        state.stubbedAlgorithm = nil
        do {
            try await encryptor.ensureRoomKeysShared(roomId: roomId)
            XCTFail("Should not succeed")
        } catch {
            XCTAssertNil(handler.roomSettings(roomId: roomId))
        }
        
        // Invalid algorithm -> throws + nothing stored
        state.stubbedAlgorithm = "blabla"
        do {
            try await encryptor.ensureRoomKeysShared(roomId: roomId)
            XCTFail("Should not succeed")
        } catch {
            XCTAssertNil(handler.roomSettings(roomId: roomId))
        }
        
        // Valid -> algorithm stored
        state.stubbedAlgorithm = kMXCryptoMegolmAlgorithm
        try await encryptor.ensureRoomKeysShared(roomId: roomId)
        XCTAssertEqual(handler.roomSettings(roomId: roomId)?.algorithm, .megolmV1AesSha2)
        
        // Another invalid algorithm -> previous algorithm kept without throwing
        state.stubbedAlgorithm = "blabla"
        try await encryptor.ensureRoomKeysShared(roomId: roomId)
        XCTAssertEqual(handler.roomSettings(roomId: roomId)?.algorithm, .megolmV1AesSha2)
        
        // Another valid -> succeeds
        state.stubbedAlgorithm = kMXCryptoOlmAlgorithm
        try await encryptor.ensureRoomKeysShared(roomId: roomId)
        XCTAssertEqual(handler.roomSettings(roomId: roomId)?.algorithm, .olmV1Curve25519AesSha2)
    }
    
    func test_ensureRoomKeysShared_correctSettings() async throws {
        try await encryptor.ensureRoomKeysShared(roomId: roomId)
        
        let settings = handler.sharedSettings
        XCTAssertEqual(settings?.algorithm, .megolmV1AesSha2)
        XCTAssertEqual(settings?.rotationPeriod, 7 * 24 * 3600)
        XCTAssertEqual(settings?.rotationPeriodMsgs, 100)
    }
    
    func test_ensureRoomKeysShared_correctHistoryVisibility() async throws {
        let stateToSettings: [(MXRoomHistoryVisibility?, HistoryVisibility)] = [
            (nil, .joined),
            (.worldReadable, .worldReadable),
            (.invited, .invited),
            (.joined, .joined),
            (.shared, .shared),
        ]
        
        for (state, settings) in stateToSettings {
            room.stubbedState?.stubbedHistoryVisibility = state
            try await encryptor.ensureRoomKeysShared(roomId: roomId)
            XCTAssertEqual(handler.sharedSettings?.historyVisibility, settings)
        }
    }
    
    func test_ensureRoomKeysShared_correctAllowTrustedDevices() async throws {
        let storeToSettings: [((Bool, Bool), Bool)] = [
            ((false, false), false),
            ((true, false), true),
            ((false, true), true),
            ((true, true), true),
        ]
        
        for ((global, perRoom), settings) in storeToSettings {
            handler.onlyAllowTrustedDevices = global
            handler.stubbedRoomSettings[roomId] = .init(
                algorithm: .megolmV1AesSha2,
                onlyAllowTrustedDevices: perRoom
            )
            
            try await encryptor.ensureRoomKeysShared(roomId: roomId)
            
            XCTAssertEqual(handler.sharedSettings?.onlyAllowTrustedDevices, settings)
        }
    }
    
    func test_ensureRoomKeysShared_correctEligibleUsers() async throws {
        members.stubbedMembers = [
            .init(userId: "Alice"),
            .init(userId: "Bob"),
            .init(userId: "Carol"),
        ]
        members.eligibleUsers = ["Alice", "Carol"]
        
        try await encryptor.ensureRoomKeysShared(roomId: roomId)
        
        XCTAssertEqual(handler.sharedUsers, ["Alice", "Carol"])
    }
    
    func test_ensureRoomKeysShared_tracksMissingUsers() async throws {
        members.stubbedMembers = [
            .init(userId: "Alice"),
            .init(userId: "Bob"),
            .init(userId: "Carol"),
        ]
        members.eligibleUsers = ["Alice", "Bob", "Carol"]
        handler.trackedUsers = ["Alice"]
        
        try await encryptor.ensureRoomKeysShared(roomId: roomId)
        
        XCTAssertEqual(handler.trackedUsers, ["Alice", "Bob", "Carol"])
    }
    
    // MARK: - Encrypt
    
    func test_encrypt_ensuresEncryptionAndKeys() async throws {
        XCTAssertFalse(encryptor.isRoomEncrypted(roomId: roomId))
        
        _ = try await encryptor.encrypt(
            content: ["body": "Hello"],
            eventType: kMXEventTypeStringRoomMessage,
            in: room
        )
        
        XCTAssertNotNil(handler.sharedSettings)
        XCTAssertEqual(handler.roomSettings(roomId: roomId)?.algorithm, .megolmV1AesSha2)
    }
    
    func test_encrypt_returnsEncryptedContent() async throws {
        let result = try await encryptor.encrypt(
            content: ["body": "Hello"],
            eventType: kMXEventTypeStringRoomMessage,
            in: room
        )
        
        XCTAssertEqual(result["ciphertext"] as? [String: String], ["body": "Hello"])
    }
}

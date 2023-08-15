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
import MatrixSDKCrypto
@testable import MatrixSDK

class MXCryptoMachineUnitTests: XCTestCase {
    enum Error: Swift.Error {
        case invalidEvent
    }
    
    class KeyProvider: NSObject, MXKeyProviderDelegate {
        func isEncryptionAvailableForData(ofType dataType: String) -> Bool {
            return true
        }
        
        func hasKeyForData(ofType dataType: String) -> Bool {
            return true
        }
        
        func keyDataForData(ofType dataType: String) -> MXKeyData? {
            MXRawDataKey(key: "1234".data(using: .ascii)!)
        }
    }
    
    var myUserId = "@alice:localhost"
    var myDeviceId = "ABCD"
    var otherUserId = "@bob:localhost"
    var roomId = "!1234:localhost"
    var verificationRequestId = "$12345"
    var restClient: MXRestClientStub!
    var machine: MXCryptoMachine!
    
    override func setUp() {
        restClient = MXRestClientStub()
        machine = try! createMachine()
    }
    
    override func tearDown() {
        do {
            try deleteData(userId: myUserId)
        } catch {
            XCTFail("Cannot tear down test - \(error)")
        }
    }
    
    // MARK: - Helpers
    
    private func createMachine(userId: String? = nil, deviceId: String? = nil) throws -> MXCryptoMachine {
        MXKeyProvider.sharedInstance().delegate = KeyProvider()
        let machine = try MXCryptoMachine(
            userId: userId ?? myUserId,
            deviceId: deviceId ?? myDeviceId,
            restClient: restClient,
            getRoomAction: {
                MXRoom(roomId: $0, andMatrixSession: nil)
            })
        MXKeyProvider.sharedInstance().delegate = nil
        return machine
    }
    
    private func deleteData(userId: String) throws {
        let url = try MXCryptoMachineStore.storeURL(for: userId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }
    
    // MARK: - Init
    
    func test_init_createsMachine() throws {
        let machine = try createMachine(userId: myUserId, deviceId: myDeviceId)
        
        XCTAssertEqual(machine.userId, myUserId)
        XCTAssertEqual(machine.deviceId, myDeviceId)
    }
    
    func test_init_createsMachinesWithDifferentDeviceIds() throws {
        let machine1 = try createMachine(deviceId: "Device1")
        XCTAssertEqual(machine1.userId, myUserId)
        XCTAssertEqual(machine1.deviceId, "Device1")
        
        let machine2 = try createMachine(deviceId: "Device2")
        XCTAssertEqual(machine2.userId, myUserId)
        XCTAssertEqual(machine2.deviceId, "Device2")
        
        let machine3 = try createMachine(deviceId: "Device3")
        XCTAssertEqual(machine3.userId, myUserId)
        XCTAssertEqual(machine3.deviceId, "Device3")
    }
    
    func test_init_loadsExistingData() throws {
        let machine1 = try createMachine()
        try machine1.setRoomAlgorithm(roomId: roomId, algorithm: .megolmV1AesSha2)
        
        let machine2 = try createMachine()
        let settings = machine2.roomSettings(roomId: roomId)
        XCTAssertEqual(settings?.algorithm, .megolmV1AesSha2)
    }
    
    func test_init_differentDeviceDeletesExistingData() throws {
        let device1 = "Device1"
        let device2 = "Device2"
        
        // Create a machine with some data
        let machine1 = try createMachine(deviceId: device1)
        try machine1.setRoomAlgorithm(roomId: roomId, algorithm: .megolmV1AesSha2)

        // Create another machine with different device ID, which will delete existing data
        let machine2 = try createMachine(deviceId: device2)
        XCTAssertNil(machine2.roomSettings(roomId: roomId))
        
        // Now opening the first machine again shows data has been removed
        let machine3 = try createMachine(deviceId: device1)
        XCTAssertNil(machine3.roomSettings(roomId: roomId))
    }
    
    func test_init_differentUserPreservesExistingData() throws {
        let user1 = "@User1:localhost"
        let user2 = "@User2:localhost"
        
        let machine1 = try createMachine(userId: user1)
        try machine1.setRoomAlgorithm(roomId: roomId, algorithm: .megolmV1AesSha2)

        let machine2 = try createMachine(userId: user2)
        try machine2.setRoomAlgorithm(roomId: roomId, algorithm: .olmV1Curve25519AesSha2)
        
        // Loading up machine1 again will have previous data unchanged
        let machine3 = try createMachine(userId: user1)
        let settings = machine3.roomSettings(roomId: roomId)
        XCTAssertEqual(settings?.algorithm, .megolmV1AesSha2)
        
        try deleteData(userId: user1)
        try deleteData(userId: user2)
    }
    
    // MARK: - Sync response
    
    func test_handleSyncResponse_canProcessEmptyResponse() async throws {
        let result = try await machine.handleSyncResponse(
            toDevice: nil,
            deviceLists: nil,
            deviceOneTimeKeysCounts: [:],
            unusedFallbackKeys: nil,
            nextBatchToken: ""
        )
        XCTAssertEqual(result.events.count, 0)
    }
    
    func test_handleSyncResponse_canProcessToDeviceEvents() async throws {
        let toDevice = MXToDeviceSyncResponse()
        toDevice.events = [
            .fixture(type: "m.key.verification.request")
        ]
        let deviceList = MXDeviceListResponse()
        deviceList.changed = ["A", "B"]
        deviceList.left = ["C", "D"]
        
        let result = try await machine.handleSyncResponse(
            toDevice: toDevice,
            deviceLists: deviceList,
            deviceOneTimeKeysCounts: [:],
            unusedFallbackKeys: nil,
            nextBatchToken: ""
        )
        XCTAssertEqual(result.events.count, 1)
    }
    
    // MARK: - Verification events
    
    func test_receiveUnencryptedVerificationEvent() async throws {
        let event = try makeUnencryptedRequestEvent()
                
        try await machine.receiveVerificationEvent(event: event, roomId: roomId)
        
        let requests = machine.verificationRequests(userId: otherUserId)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.state(), .requested)
    }
    
    func test_receiveEncryptedVerificationEvent() async throws {
        // Start verification by recieving `m.key.verifiaction.request` from the other user
        let requestEvent = try makeUnencryptedRequestEvent()
        try await machine.receiveVerificationEvent(event: requestEvent, roomId: roomId)
        let request = machine.verificationRequests(userId: otherUserId).first
        XCTAssertNotNil(request)
        
        let cancelEvent = try makeDecryptedCancelEvent()
           
        try await machine.receiveVerificationEvent(event: cancelEvent, roomId: roomId)
        
        XCTAssertEqual(request?.state(), .cancelled(
            cancelInfo: .init(
                reason: "The user cancelled the verification.",
                cancelCode: "m.user",
                cancelledByUs: false
            )
        ))
    }
    
    // MARK: - Helpers
    
    private func makeUnencryptedRequestEvent() throws -> MXEvent {
        guard let event = MXEvent(fromJSON: [
            "origin_server_ts": Date().timeIntervalSince1970 * 1000,
            "event_id": verificationRequestId,
            "sender": otherUserId,
            "type": "m.room.message",
            "content": [
                "msgtype": "m.key.verification.request",
                "from_device": "ABC",
                "to": myUserId,
                "body": "",
                "methods": ["m.sas.v1"]
            ]
        ]) else {
            throw Error.invalidEvent
        }
        return event
    }
    
    private func makeDecryptedCancelEvent() throws -> MXEvent {
        guard let decrypted = MXEvent(fromJSON: [
            "origin_server_ts": Date().timeIntervalSince1970 * 1000,
            "event_id": verificationRequestId,
            "sender": otherUserId,
            "type": "m.room.encrypted",
            "content": [
                "algorithm": kMXCryptoMegolmAlgorithm,
                "ciphertext": "ABCDEFGH",
                "sender_key": "ABCD",
                "device_id": "ABCD",
                "session_id": "1234"
            ]
        ]) else {
            throw Error.invalidEvent
        }
        
        let result = try MXEventDecryptionResult(event: .stub(clearEvent: [
            "event_id": "$6789",
            "sender": otherUserId,
            "type": "m.key.verification.cancel",
            "content": [
                "code": "m.user",
                "reason": "User rejected the key verification request",
                "transaction_id": verificationRequestId,
                "m.relates_to": [
                    "event_id": verificationRequestId,
                    "rel_type": "m.reference"
                ]
            ]
        ]))
        decrypted.setClearData(result)
        return decrypted
    }
}

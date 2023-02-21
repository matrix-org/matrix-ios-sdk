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
    var otherUserId = "@bob:localhost"
    var roomId = "!1234:localhost"
    var verificationRequestId = "$12345"
    var restClient: MXRestClientStub!
    var machine: MXCryptoMachine!
    
    override func setUp() {
        restClient = MXRestClientStub()
        MXKeyProvider.sharedInstance().delegate = KeyProvider()
        machine = try! MXCryptoMachine(
            userId: myUserId,
            deviceId: "ABCD",
            restClient: restClient,
            getRoomAction: {
                MXRoom(roomId: $0, andMatrixSession: nil)
            })
        MXKeyProvider.sharedInstance().delegate = nil
    }
    
    override func tearDown() {
        do {
            let url = try MXCryptoMachineStore.storeURL(for: myUserId)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return
            }
            try FileManager.default.removeItem(at: url)
        } catch {
            XCTFail("Cannot tear down test - \(error)")
        }
    }
    
    // MARK: - Sync response
    
    func test_handleSyncResponse_canProcessEmptyResponse() async throws {
        let result = try await machine.handleSyncResponse(
            toDevice: nil,
            deviceLists: nil,
            deviceOneTimeKeysCounts: [:],
            unusedFallbackKeys: nil
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
            unusedFallbackKeys: nil
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
                cancelCode: "m.user",
                reason: "The user cancelled the verification.",
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

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
@_implementationOnly import MatrixSDKCrypto
@testable import MatrixSDK

class MXMegolmDecryptionUnitTests: XCTestCase {
    /// Spy session used to assert on the results of the test
    struct SpySession: Equatable {
        let sharedHistory: Bool
    }
    
    /// Spy olm device used to collect spy sessions for the purpose of test assertions
    class DeviceStub: MXOlmDevice {
        var sessions: [SpySession] = []
        
        override func addInboundGroupSession(
            _ sessionId: String!,
            sessionKey: String!,
            roomId: String!,
            senderKey: String!,
            forwardingCurve25519KeyChain: [String]!,
            keysClaimed: [String : String]!,
            exportFormat: Bool,
            sharedHistory: Bool,
            untrusted: Bool
        ) -> Bool {
            sessions.append(
                .init(sharedHistory: sharedHistory)
            )
            return true
        }
        
        var stubbedResult: MXDecryptionResult?
        
        override func decryptGroupMessage(
            _ body: String!,
            isEditEvent: Bool,
            roomId: String!,
            inTimeline timeline: String!,
            sessionId: String!,
            senderKey: String!
        ) throws -> MXDecryptionResult {
            stubbedResult ?? MXDecryptionResult()
        }
    }
    
    /// Stub of the session which returns a preconfigured summary of rooms
    class SessionStub: MXSession {
        var historyVisibility: String = kMXRoomHistoryVisibilityWorldReadable
        
        override func room(withRoomId roomId: String!) -> MXRoom! {
            return MXRoom(roomId: roomId, andMatrixSession: self)
        }
        
        override func roomSummary(withRoomId roomId: String!) -> MXRoomSummary! {
            let summary = MXRoomSummary()
            summary.historyVisibility = historyVisibility
            return summary
        }
    }
    
    class CryptoStoreStub: MXRealmCryptoStore {
        var sessions: [String: MXOlmInboundGroupSession] = [:]
        
        override func inboundGroupSession(
            withId sessionId: String!,
            andSenderKey senderKey: String!
        ) -> MXOlmInboundGroupSession! {
            return sessions["\(sessionId!)-\(senderKey!)"]
        }
    }
    
    /// Stub of crypto which connects various other stubbed objects (device, session)
    class CryptoStub: MXLegacyCrypto {
        private let device: MXOlmDevice
        private let cryptoStore: MXCryptoStore
        private let session: MXSession
        private let devices: MXDeviceList
        
        init(device: MXOlmDevice, store: MXCryptoStore, session: MXSession, devices: MXDeviceList) {
            self.device = device
            self.cryptoStore = store
            self.session = session
            self.devices = devices
        }
        
        override var olmDevice: MXOlmDevice! {
            return device
        }
        
        override var cryptoQueue: DispatchQueue! {
            return DispatchQueue.main
        }
        
        override var store: MXCryptoStore! {
            return cryptoStore
        }
        
        override var mxSession: MXSession! {
            return session
        }
        
        override var deviceList: MXDeviceList! {
            return devices
        }
        
        override func trustLevel(forUser userId: String) -> MXUserTrustLevel {
            return MXUserTrustLevel(crossSigningVerified: true, locallyVerified: true)
        }
    }
    
    class DeviceListStub: MXDeviceList {
        var stubbedDevices = [String: Device]()
        override func device(withIdentityKey senderKey: String!, andAlgorithm algorithm: String!) -> MXDeviceInfo! {
            guard algorithm != nil, let senderKey = senderKey, let device = stubbedDevices[senderKey] else {
                return nil
            }
            
            return .init(device: .init(device: device))
        }
    }
    
    let roomId1 = "ABC"
    let roomId2 = "XYZ"
    let sessionId1 = "123"
    let sessionId2 = "999"
    let senderKey = "456"
    
    var device: DeviceStub!
    var store: CryptoStoreStub!
    var session: SessionStub!
    var crypto: CryptoStub!
    var devicesList: DeviceListStub!
    var decryption: MXMegolmDecryption!
    
    override func setUp() {
        super.setUp()
        
        device = DeviceStub()
        store = CryptoStoreStub()
        session = SessionStub()
        devicesList = DeviceListStub()
        crypto = CryptoStub(device: device, store: store, session: session, devices: devicesList)
        decryption = MXMegolmDecryption(crypto: crypto)
    }
    
    // Ensure that `sharedHistory` is added to an inbound session only
    // if explicitly set by the room key event
    func test_onRoomKeyEvent_addsSessionSharedHistoryFromEvent() {
        MXSDKOptions.sharedInstance().enableRoomSharedHistoryOnInvite = true
        
        // Configure a set of event values and outcome values where `sharedHistory`
        // on the final session is set to whatever value the event has, defaulting
        // to false if not specified. This is even if the room's history is currently
        // set to shared or world readable
        let eventToExpectation: [(Bool?, Bool)] = [
            (nil, false),
            (false, false),
            (true, true)
        ]
        session.historyVisibility = kMXRoomHistoryVisibilityWorldReadable
        
        for (eventValue, expectedValue) in eventToExpectation {
            let event = MXEvent.roomKeyFixture(
                sharedHistory: eventValue
            )
            device.sessions = []
            
            decryption.onRoomKeyEvent(event)
            
            XCTAssertEqual(device.sessions.count, 1)
            XCTAssertEqual(device.sessions.first, SpySession(sharedHistory: expectedValue))
        }
    }
    
    // Ensure that checking for the presence of shared history, only session
    // with matching roomId is queried
    func test_hasSharedHistory_queriesSessionWithMatchingRoomId() {
        // Parametrize the test via a configuration and a set of cases
        // with expected outcome
        struct Configuration {
            let sharedHistory: Bool
            let sessionId: String
            let roomId: String
        }
        let allCases = [
            
            // Mismatched session id -> does not have keys
            (
                Configuration(
                    sharedHistory: true,
                    sessionId: sessionId2,
                    roomId: roomId1
                ),
                false
            ),
            
            // Mismatched room id -> does not have keys
            (
                Configuration(
                    sharedHistory: true,
                    sessionId: sessionId1,
                    roomId: roomId2
                ),
                false
            ),
            
            // Matching session and room id but not sharing history -> does not have keys
            (
                Configuration(
                    sharedHistory: false,
                    sessionId: sessionId1,
                    roomId: roomId1
                ),
                false
            ),
            
            // Matching session and room id and sharing history -> has keys
            (
                Configuration(
                    sharedHistory: true,
                    sessionId: sessionId1,
                    roomId: roomId1
                ),
                true
            )
        ]
        
        for (config, expectedValue) in allCases {
            let session = MXOlmInboundGroupSession()
            session.sharedHistory = config.sharedHistory
            session.roomId = config.roomId
            
            store.sessions = [
                "\(config.sessionId)-\(senderKey)": session
            ]
            
            let hasSharedHistory = decryption.hasSharedHistory(forRoomId: roomId1, sessionId: sessionId1, senderKey: senderKey)
            XCTAssertEqual(hasSharedHistory, expectedValue)
        }
    }
    
    func test_decryptEvent_untrustedResult() {
        let event = MXEvent.encryptedFixture()
        device.stubbedResult = MXDecryptionResult()
        device.stubbedResult?.senderKey = "ABCD"
        
        devicesList.stubbedDevices = [
            "ABCD": Device.stub(
                locallyTrusted: false,
                crossSigningTrusted: true
            )
        ]
        
        device.stubbedResult?.isUntrusted = true
        let result1 = decryption.decryptEvent(event, inTimeline: nil)
        XCTAssertEqual(result1?.decoration.color, .grey)
        
        device.stubbedResult?.isUntrusted = false
        let result2 = decryption.decryptEvent(event, inTimeline: nil)
        XCTAssertEqual(result2?.decoration.color, MXEventDecryptionDecorationColor.none)
    }
    
    func test_decryptEvent_untrustedDevice() {
        let event = MXEvent.encryptedFixture()
        device.stubbedResult = MXDecryptionResult()
        device.stubbedResult?.senderKey = "XYZ"
        
        devicesList.stubbedDevices = [
            "XYZ": Device.stub(
                locallyTrusted: false,
                crossSigningTrusted: false
            )
        ]
        let result1 = decryption.decryptEvent(event, inTimeline: nil)
        XCTAssertEqual(result1?.decoration.color, .red)
        
        devicesList.stubbedDevices = [
            "XYZ": Device.stub(
                locallyTrusted: false,
                crossSigningTrusted: true
            )
        ]
        let result2 = decryption.decryptEvent(event, inTimeline: nil)
        XCTAssertEqual(result2?.decoration.color, MXEventDecryptionDecorationColor.none)
    }
    
    func test_decryptEvent_unknownDevice() {
        let invalidKey = "123"
        let validKey = "456"
        
        let event = MXEvent.encryptedFixture()
        device.stubbedResult = MXDecryptionResult()
        device.stubbedResult?.senderKey = validKey
        
        let stub = Device.stub(
            locallyTrusted: true,
            crossSigningTrusted: true
        )
        
        devicesList.stubbedDevices = [
            invalidKey: stub
        ]
        let result1 = decryption.decryptEvent(event, inTimeline: nil)
        XCTAssertEqual(result1?.decoration.color, .red)
        
        devicesList.stubbedDevices = [
            validKey: stub
        ]
        let result2 = decryption.decryptEvent(event, inTimeline: nil)
        XCTAssertEqual(result2?.decoration.color, MXEventDecryptionDecorationColor.none)
    }
}

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
import XCTest
@_implementationOnly import MatrixSDKCrypto
@testable import MatrixSDK

class MXCryptoMigrationStoreUnitTests: XCTestCase {
    
    var pickleKey: Data!
    var legacyStore: MXMemoryCryptoStore!
    var store: MXCryptoMigrationStore!
    
    override func setUp() {
        pickleKey = "1234".data(using: .ascii)!
        
        let credentials = MXCredentials()
        credentials.userId = "Alice"
        credentials.deviceId = "ABC"
        
        legacyStore = MXMemoryCryptoStore(credentials: credentials)
        legacyStore.setAccount(OLMAccount(newAccount: ()))
        
        store = .init(legacyStore: legacyStore)
    }
    
    // MARK: - Helpers
    
    func extractData(pickleKey: Data? = nil) throws -> MigrationData {
        try store.extractData(with: pickleKey ?? self.pickleKey)
    }
    
    func extractSessions(pickleKey: Data? = nil) throws -> [PickledSession] {
        var sessions = [PickledSession]()
        store.extractSessions(with: pickleKey ?? self.pickleKey, batchSize: .max) { batch, progress in
            sessions += batch
        }
        return sessions
    }
    
    func extractGroupSessions(pickleKey: Data? = nil) throws -> [PickledInboundGroupSession] {
        var sessions = [PickledInboundGroupSession]()
        store.extractGroupSessions(with: pickleKey ?? self.pickleKey, batchSize: .max) { batch, progress in
            sessions += batch
        }
        return sessions
    }
    
    @discardableResult
    func storeGroupSession(
        roomId: String = "ABC",
        senderKey: String? = "Bob",
        isUntrusted: Bool = false,
        backedUp: Bool = false
    ) -> MXOlmInboundGroupSession {
        let device = MXOlmDevice(store: legacyStore)!
        let outbound = device.createOutboundGroupSessionForRoom(withRoomId: roomId)
        
        let session = MXOlmInboundGroupSession(sessionKey: outbound!.sessionKey)!
        session.senderKey = senderKey
        session.roomId = roomId
        session.keysClaimed = ["A": "1"]
        session.isUntrusted = isUntrusted
        legacyStore.store([session])
        
        if backedUp {
            legacyStore.markBackupDone(for: [session])
        }
        return session
    }
    
    func storeSecret(_ secret: String, secretId: Unmanaged<NSString>) {
        legacyStore.storeSecret(secret, withSecretId: secretId.takeUnretainedValue() as String)
    }
    
    // MARK: - Tests
    
    func test_credentials() {
        XCTAssertEqual(store.userId, "Alice")
        XCTAssertEqual(store.deviceId, "ABC")
    }
    
    func test_trustedSettings() {
        legacyStore.globalBlacklistUnverifiedDevices = false
        XCTAssertFalse(store.globalSettings.onlyAllowTrustedDevices)
        
        legacyStore.globalBlacklistUnverifiedDevices = true
        XCTAssertTrue(store.globalSettings.onlyAllowTrustedDevices)
    }
    
    func test_missingAccountFailsExtraction() {
        legacyStore.setAccount(nil)
        do {
            _ = try extractData()
            XCTFail("Should not succeed")
        } catch MXCryptoMigrationStore.Error.missingAccount {
            XCTAssert(true)
        } catch {
            XCTFail("Unknown error")
        }
    }
    
    func test_extractsAccount() throws {
        let legacyPickle = try legacyStore.account().serializeData(withKey: pickleKey)
        
        let account = try extractData().account
        
        XCTAssertEqual(account.userId, "Alice")
        XCTAssertEqual(account.deviceId, "ABC")
        XCTAssertEqual(account.pickle, legacyPickle)
        XCTAssertTrue(account.shared)
        XCTAssertEqual(account.uploadedSignedKeyCount, 50)
    }
    
    func test_extractsSession() throws {
        let session = MXOlmSession(olmSession: OLMSession(), deviceKey: "XYZ")
        session.lastReceivedMessageTs = 123
        legacyStore.store(session)
        let pickle = try session.session.serializeData(withKey: pickleKey)
        
        // There are no sessions in the general migration data
        XCTAssertTrue(try extractData().sessions.isEmpty)
        
        // But they can be accumulated by batching
        let sessions = try extractSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].pickle, pickle)
        XCTAssertEqual(sessions[0].senderKey, "XYZ")
        XCTAssertFalse(sessions[0].createdUsingFallbackKey)
        XCTAssertEqual(sessions[0].creationTime, "123")
        XCTAssertEqual(sessions[0].lastUseTime, "123")
    }
    
    func test_extractsMultipleSessionsInBatches() throws {
        for i in 0 ..< 12 {
            legacyStore.store(MXOlmSession(olmSession: OLMSession(), deviceKey: "\(i)"))
        }
        
        // There are no sessions in the general migration data
        XCTAssertTrue(try extractData().sessions.isEmpty)
        // But they can be accumulated by batching
        let sessions = try extractSessions()
        XCTAssertEqual(sessions.count, 12)
    }
    
    func test_extractsGroupSession() throws {
        let session = storeGroupSession(roomId: "abcd")
        let pickle = try session.session.serializeData(withKey: pickleKey)
        
        // There are no sessions in the general migration data
        XCTAssertTrue(try extractData().inboundGroupSessions.isEmpty)
        
        // But they can be accumulated by batching
        let sessions = try extractGroupSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].pickle, pickle)
        XCTAssertEqual(sessions[0].senderKey, "Bob")
        XCTAssertEqual(sessions[0].signingKey, ["A": "1"])
        XCTAssertEqual(sessions[0].roomId, "abcd")
        XCTAssertEqual(sessions[0].forwardingChains, [])
    }
    
    func test_extractsOnlyValidGroupSessions() throws {
        for i in 0 ..< 4 {
            let isValid = i % 2 == 0
            storeGroupSession(senderKey: isValid ? "Bob" : nil)
        }
        
        // There are no sessions in the general migration data
        XCTAssertTrue(try extractData().inboundGroupSessions.isEmpty)
        
        // But they can be accumulated by batching
        let sessions = try extractGroupSessions()
        XCTAssertEqual(sessions.count, 2)
    }
    
    func test_extractsImportedGroupSessionStatus() throws {
        storeGroupSession(isUntrusted: true)
        storeGroupSession(isUntrusted: false)
        storeGroupSession(isUntrusted: false)
        
        let sessions = try extractGroupSessions()
        
        XCTAssertEqual(sessions.count, 3)
        XCTAssertTrue(sessions[0].imported)
        XCTAssertFalse(sessions[1].imported)
        XCTAssertFalse(sessions[1].imported)
    }
    
    func test_extractsBackedUpGroupSessionStatus() throws {
        storeGroupSession(backedUp: false)
        storeGroupSession(backedUp: true)
        storeGroupSession(backedUp: false)
        
        let sessions = try extractGroupSessions()
        
        XCTAssertEqual(sessions.count, 3)
        XCTAssertFalse(sessions[0].backedUp)
        XCTAssertTrue(sessions[1].backedUp)
        XCTAssertFalse(sessions[2].backedUp)
    }
    
    func test_extractsBackupVersion() throws {
        legacyStore.backupVersion = "5"
        let version = try extractData().backupVersion
        XCTAssertEqual(version, "5")
    }
    
    func test_extractsBackupRecoveryKey() throws {
        let privateKey = "ABCD"
        storeSecret(privateKey, secretId: MXSecretId.keyBackup)
        
        let key = try extractData().backupRecoveryKey
        
        let recovery = MXRecoveryKey.encode(MXBase64Tools.data(fromBase64: privateKey))
        XCTAssertNotNil(key)
        XCTAssertNotNil(recovery)
        XCTAssertEqual(key, recovery)
    }
    
    func test_extractsPickeKey() throws {
        let pickleKey = "some key".data(using: .ascii)!
        let key = try extractData(pickleKey: pickleKey).pickleKey
        XCTAssertEqual(key, [UInt8](pickleKey))
    }
    
    func test_extractsCrossSigning() throws {
        storeSecret("MASTER", secretId: MXSecretId.crossSigningMaster)
        storeSecret("USER", secretId: MXSecretId.crossSigningUserSigning)
        storeSecret("SELF", secretId: MXSecretId.crossSigningSelfSigning)
        
        let crossSigning = try extractData().crossSigning
        
        XCTAssertEqual(crossSigning.masterKey, "MASTER")
        XCTAssertEqual(crossSigning.userSigningKey, "USER")
        XCTAssertEqual(crossSigning.selfSigningKey, "SELF")
    }
    
    func test_extractsOnlyTrackedUsers() throws {
        let users = [
            "Alice": MXDeviceTrackingStatusNotTracked,
            "Bob": MXDeviceTrackingStatusPendingDownload,
            "Carol": MXDeviceTrackingStatusDownloadInProgress,
            "Dave": MXDeviceTrackingStatusUpToDate,
        ].mapValues { NSNumber(value: $0.rawValue) }
        legacyStore.storeDeviceTrackingStatus(users)
        
        let trackedUsers = try extractData().trackedUsers
        
        XCTAssertEqual(Set(trackedUsers), ["Bob", "Carol", "Dave"])
    }
    
    func test_extractsRoomSettings() throws {
        legacyStore.storeAlgorithm(forRoom: "room1", algorithm: kMXCryptoOlmAlgorithm)
        legacyStore.storeBlacklistUnverifiedDevices(inRoom: "room1", blacklist: true)
        
        legacyStore.storeAlgorithm(forRoom: "room2", algorithm: kMXCryptoMegolmAlgorithm)
        legacyStore.storeBlacklistUnverifiedDevices(inRoom: "room2", blacklist: false)
        
        legacyStore.storeAlgorithm(forRoom: "room3", algorithm: "something invalid")
        legacyStore.storeBlacklistUnverifiedDevices(inRoom: "room3", blacklist: true)
        
        let settings = try extractData().roomSettings
        
        XCTAssertEqual(settings, [
            "room1": RoomSettings(algorithm: .olmV1Curve25519AesSha2, onlyAllowTrustedDevices: true),
            "room2": RoomSettings(algorithm: .megolmV1AesSha2, onlyAllowTrustedDevices: false),
        ])
    }
}

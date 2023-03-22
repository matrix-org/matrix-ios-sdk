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
import MatrixSDKCrypto
@testable import MatrixSDK

class MXCryptoMigrationV2Tests: XCTestCase {
    enum Error: Swift.Error {
        case missingDependencies
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
    
    var data: MatrixSDKTestsData!
    var e2eData: MatrixSDKTestsE2EData!
    
    override func setUp() {
        data = MatrixSDKTestsData()
        e2eData = MatrixSDKTestsE2EData(matrixSDKTestsData: data)
    }
    
    // MARK: - Helpers
    
    private func fullyMigratedOlmMachine(session: MXSession) throws -> MXCryptoMachine {
        guard
            let store = session.legacyCrypto?.store,
            let restClient = session.matrixRestClient
        else {
            throw Error.missingDependencies
        }
        
        MXKeyProvider.sharedInstance().delegate = KeyProvider()
        let migration = MXCryptoMigrationV2(legacyStore: store)
        try migration.migrateAllData { _ in }
        let machine = try MXCryptoMachine(
            userId: store.userId(),
            deviceId: store.deviceId(),
            restClient: restClient,
            getRoomAction: { _ in
                return nil
            })
        MXKeyProvider.sharedInstance().delegate = nil
        return machine
    }
    
    private func partiallyMigratedOlmMachine(session: MXSession) throws -> MXCryptoMachine {
        guard
            let store = session.legacyCrypto?.store,
            let restClient = session.matrixRestClient
        else {
            throw Error.missingDependencies
        }
        
        MXKeyProvider.sharedInstance().delegate = KeyProvider()
        let migration = MXCryptoMigrationV2(legacyStore: store)
        try migration.migrateRoomAndGlobalSettingsOnly { _ in }
        let machine = try MXCryptoMachine(
            userId: store.userId(),
            deviceId: store.deviceId(),
            restClient: restClient,
            getRoomAction: { _ in
                return nil
            })
        MXKeyProvider.sharedInstance().delegate = nil
        return machine
    }
    
    // MARK: - Tests
    
    func test_migratesAccountDetails() async throws {
        let env = try await e2eData.startE2ETest()
        let legacySession = env.session

        let machine = try self.fullyMigratedOlmMachine(session: env.session)

        XCTAssertEqual(machine.userId, legacySession.myUserId)
        XCTAssertEqual(machine.deviceId, legacySession.myDeviceId)
        XCTAssertEqual(machine.deviceCurve25519Key, legacySession.crypto.deviceCurve25519Key)
        XCTAssertEqual(machine.deviceEd25519Key, legacySession.crypto.deviceEd25519Key)
        
        await env.close()
    }
    
    func test_canDecryptMegolmMessageAfterMigration() async throws {
        let env = try await e2eData.startE2ETest()
        
        guard let room = env.session.room(withRoomId: env.roomId) else {
            throw Error.missingDependencies
        }

        // Send a new message in encrypted room
        let event = try await room.sendTextMessage("Hi bob")

        // Erase cleartext and make sure the event was indeed encrypted
        event.setClearData(nil)
        XCTAssertTrue(event.isEncrypted)
        XCTAssertEqual(event.content["algorithm"] as? String, kMXCryptoMegolmAlgorithm)
        XCTAssertNotNil(event.content["ciphertext"])

        // Migrate the session to crypto v2
        let machine = try self.fullyMigratedOlmMachine(session: env.session)

        // Decrypt the event using crypto v2
        let decrypted = try machine.decryptRoomEvent(event)
        let result = try MXEventDecryptionResult(event: decrypted)
        let content = result.clearEvent["content"] as? [String: Any]

        // At this point we should be able to read back the original message after
        // having decrypted the event with room keys migrated earlier
        XCTAssertEqual(content?["body"] as? String, "Hi bob")
        
        await env.close()
    }
    
    func test_notCrossSignedAfterMigration() async throws {
        let env = try await e2eData.startE2ETest()
        
        // We start with user who cannot cross-sign (did not setup cross signing keys)
        let legacyCrossSigning = env.session.crypto.crossSigning
        XCTAssertFalse(legacyCrossSigning.canCrossSign)
        XCTAssertFalse(legacyCrossSigning.hasAllPrivateKeys)
        
        // We then migrate the user into crypto v2
        let machine = try fullyMigratedOlmMachine(session: env.session)
        let crossSigningV2 = MXCrossSigningV2(crossSigning: machine, restClient: env.session.matrixRestClient)
        try await crossSigningV2.refreshState()
        
        // As expected we cannot cross sign in v2 either
        XCTAssertFalse(crossSigningV2.canCrossSign)
        XCTAssertFalse(crossSigningV2.hasAllPrivateKeys)
        
        await env.close()
    }
    
    func test_migratesCrossSigningStatus() async throws {
        let env = try await e2eData.startE2ETest()
        
        // We start with user who setup cross-signing with password
        let legacyCrossSigning = env.session.crypto.crossSigning
        try await legacyCrossSigning.setup(withPassword: MXTESTS_ALICE_PWD)
        XCTAssertTrue(legacyCrossSigning.canCrossSign)
        XCTAssertTrue(legacyCrossSigning.hasAllPrivateKeys)
        
        // We now migrate the data into crypto v2
        let machine = try fullyMigratedOlmMachine(session: env.session)
        let crossSigningV2 = MXCrossSigningV2(crossSigning: machine, restClient: env.session.matrixRestClient)
        try await crossSigningV2.refreshState()

        // And confirm that cross signing is ready
        XCTAssertTrue(crossSigningV2.canCrossSign)
        XCTAssertTrue(crossSigningV2.hasAllPrivateKeys)
        
        await env.close()
    }
    
    func test_migratesRoomSettings() async throws {
        let env = try await e2eData.startE2ETest()
        
        // We start with user and encrypted room with some settings
        let legacyCrypto = env.session.crypto!
        try await legacyCrypto.ensureEncryption(roomId: env.roomId)
        legacyCrypto.setBlacklistUnverifiedDevicesInRoom(env.roomId, blacklist: true)
        XCTAssertTrue(legacyCrypto.isRoomEncrypted(env.roomId))
        XCTAssertTrue(legacyCrypto.isBlacklistUnverifiedDevices(inRoom: env.roomId))

        // We now migrate the data into crypto v2
        let machine = try fullyMigratedOlmMachine(session: env.session)

        // And confirm that room settings have been migrated
        let settings = machine.roomSettings(roomId: env.roomId)
        XCTAssertEqual(settings, .init(algorithm: .megolmV1AesSha2, onlyAllowTrustedDevices: true))
        
        await env.close()
    }
    
    func test_migratesRoomSettingsInPartialMigration() async throws {
        let env = try await e2eData.startE2ETest()
        
        // We start with user and encrypted room with some settings
        let legacyCrypto = env.session.crypto!
        try await legacyCrypto.ensureEncryption(roomId: env.roomId)
        legacyCrypto.setBlacklistUnverifiedDevicesInRoom(env.roomId, blacklist: true)
        XCTAssertTrue(legacyCrypto.isRoomEncrypted(env.roomId))
        XCTAssertTrue(legacyCrypto.isBlacklistUnverifiedDevices(inRoom: env.roomId))

        // We now migrate the data into crypto v2
        let machine = try partiallyMigratedOlmMachine(session: env.session)

        // And confirm that room settings have been migrated
        let settings = machine.roomSettings(roomId: env.roomId)
        XCTAssertEqual(settings, .init(algorithm: .megolmV1AesSha2, onlyAllowTrustedDevices: true))
        
        await env.close()
    }
    
    func test_migratesGlobalSettings() async throws {
        let env1 = try await e2eData.startE2ETest()
        env1.session.crypto.globalBlacklistUnverifiedDevices = true
        let machine1 = try fullyMigratedOlmMachine(session: env1.session)
        XCTAssertTrue(machine1.onlyAllowTrustedDevices)
        await env1.close()
        
        let env2 = try await e2eData.startE2ETest()
        env2.session.crypto.globalBlacklistUnverifiedDevices = false
        let machine2 = try fullyMigratedOlmMachine(session: env2.session)
        XCTAssertFalse(machine2.onlyAllowTrustedDevices)
        await env2.close()
    }
    
    func test_test_migratesGlobalSettingsInPartialMigration() async throws {
        let env1 = try await e2eData.startE2ETest()
        env1.session.crypto.globalBlacklistUnverifiedDevices = true
        let machine1 = try partiallyMigratedOlmMachine(session: env1.session)
        XCTAssertTrue(machine1.onlyAllowTrustedDevices)
        await env1.close()
        
        let env2 = try await e2eData.startE2ETest()
        env2.session.crypto.globalBlacklistUnverifiedDevices = false
        let machine2 = try partiallyMigratedOlmMachine(session: env2.session)
        XCTAssertFalse(machine2.onlyAllowTrustedDevices)
        await env2.close()
    }
}

private extension MXCrypto {
    func downloadKeys(userIds: [String]) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            downloadKeys(userIds, forceDownload: false) { _, _ in
                continuation.resume()
            }
        }
    }
    
    func ensureEncryption(roomId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            ensureEncryption(inRoom: roomId) {
                continuation.resume()
            }
        }
    }
}

extension MXCrossSigning {
    func refreshState() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            refreshState { _ in
                continuation.resume()
            } failure: { error in
                continuation.resume(throwing: error)
            }
        }
    }
    
    func signUser(userId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            signUser(withUserId: userId) {
                continuation.resume()
            } failure: { error in
                continuation.resume(throwing: error)
            }
        }
    }
    
    func setup(withPassword password: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            setup(withPassword: password) {
                continuation.resume()
            } failure: { error in
                continuation.resume(throwing: error)
            }
        }
    }
}

private extension MXRoom {
    enum Error: Swift.Error {
        case cannotSendMessage
    }
    
    @MainActor
    func sendTextMessage(_ text: String) async throws -> MXEvent {
        var event: MXEvent?
        _ = try await withCheckedThrowingContinuation{ (continuation: CheckedContinuation<String?, Swift.Error>) in
            sendTextMessage(text, localEcho: &event) { response in
                switch response {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        guard let event = event else {
            throw Error.cannotSendMessage
        }
        return event
    }
}

extension MXCryptoMigrationV2Tests: Logger {
    func log(logLine: String) {
        MXLog.debug("[MXCryptoMigrationV2Tests]: \(logLine)")
    }
}

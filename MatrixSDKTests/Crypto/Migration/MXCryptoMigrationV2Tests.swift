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

#if DEBUG

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
        setLogger(logger: self)
    }
    
    // MARK: - Helpers
    
    private func migratedOlmMachine(session: MXSession) throws -> MXCryptoMachine {
        guard
            let store = session.legacyCrypto?.store,
            let restClient = session.matrixRestClient
        else {
            throw Error.missingDependencies
        }
        
        MXKeyProvider.sharedInstance().delegate = KeyProvider()
        let migration = MXCryptoMigrationV2(legacyStore: store)
        try migration.migrateCrypto()
        MXKeyProvider.sharedInstance().delegate = nil
        
        return try MXCryptoMachine(
            userId: store.userId(),
            deviceId: store.deviceId(),
            restClient: restClient,
            getRoomAction: { _ in
                return nil
            })
    }
    
    // MARK: - Tests
    
    func test_migratesAccountDetails() async throws {
        let env = try await e2eData.startE2ETest()
        let legacySession = env.session
        
        let machine = try self.migratedOlmMachine(session: env.session)
        
        XCTAssertEqual(machine.userId, legacySession.myUserId)
        XCTAssertEqual(machine.deviceId, legacySession.myDeviceId)
        XCTAssertEqual(machine.deviceCurve25519Key, legacySession.crypto.deviceCurve25519Key)
        XCTAssertEqual(machine.deviceEd25519Key, legacySession.crypto.deviceEd25519Key)
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
        let machine = try self.migratedOlmMachine(session: env.session)
        
        // Decrypt the event using crypto v2
        let decrypted = try machine.decryptRoomEvent(event)
        let result = try MXEventDecryptionResult(event: decrypted)
        let content = result.clearEvent["content"] as? [String: Any]

        // At this point we should be able to read back the original message after
        // having decrypted the event with room keys migrated earlier
        XCTAssertEqual(content?["body"] as? String, "Hi bob")
    }
    
    func test_migratesCrossSigningStatus() async throws {
        let env = try await e2eData.startE2ETest()
        
        // We start with user who cannot cross-sign (did not setup cross signing keys)
        let legacyCrossSigning = env.session.crypto.crossSigning
        XCTAssertFalse(legacyCrossSigning.canCrossSign)
        XCTAssertFalse(legacyCrossSigning.hasAllPrivateKeys)
        
        // We then migrate the user into crypto v2
        var machine = try migratedOlmMachine(session: env.session)
        var crossSigningV2 = MXCrossSigningV2(crossSigning: machine, restClient: env.session.matrixRestClient)
        try await crossSigningV2.refreshState()
        
        // As expected we cannot cross sign in v2 either
        XCTAssertFalse(crossSigningV2.canCrossSign)
        XCTAssertFalse(crossSigningV2.hasAllPrivateKeys)
        
        // Now we setup cross-signing with password on the original / legacy session
        try await legacyCrossSigning.setup(withPassword: MXTESTS_ALICE_PWD)
        XCTAssertTrue(legacyCrossSigning.canCrossSign)
        XCTAssertTrue(legacyCrossSigning.hasAllPrivateKeys)
        
        // We have to migrate the data once again into crypto v2
        machine = try migratedOlmMachine(session: env.session)
        crossSigningV2 = MXCrossSigningV2(crossSigning: machine, restClient: env.session.matrixRestClient)
        try await crossSigningV2.refreshState()
        
        // And confirm that cross signing is ready
        XCTAssertTrue(crossSigningV2.canCrossSign)
        XCTAssertTrue(crossSigningV2.hasAllPrivateKeys)
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
}

private extension MXCrossSigning {
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
    
    func sendTextMessage(_ text: String) async throws -> MXEvent {
        var event: MXEvent?
        _ = try await performCallbackRequest {
            sendTextMessage(text, localEcho: &event, completion: $0)
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

#endif

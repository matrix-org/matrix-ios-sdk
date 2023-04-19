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

class MXCryptoMigrationV2UnitTests: XCTestCase {
    enum Error: Swift.Error {
        case missingEvent
    }
    
    override func tearDown() async throws {
        try LegacyRealmStore.deleteAllStores()
    }
    
    // MARK: - Helpers
    
    private func fullyMigratedOlmMachine(legacyStore: MXCryptoStore) throws -> MXCryptoMachine {
        MXKeyProvider.sharedInstance().delegate = MXKeyProviderStub()
        let migration = MXCryptoMigrationV2(legacyStore: legacyStore)
        try migration.migrateAllData { _ in }
        let machine = try MXCryptoMachine(
            userId: legacyStore.userId(),
            deviceId: legacyStore.deviceId(),
            restClient: MXRestClientStub(),
            getRoomAction: { _ in
                return nil
            })
        MXKeyProvider.sharedInstance().delegate = nil
        return machine
    }
    
    private func partiallyMigratedOlmMachine(legacyStore: MXCryptoStore) throws -> MXCryptoMachine {
        MXKeyProvider.sharedInstance().delegate = MXKeyProviderStub()
        let migration = MXCryptoMigrationV2(legacyStore: legacyStore)
        try migration.migrateRoomAndGlobalSettingsOnly { _ in }
        let machine = try MXCryptoMachine(
            userId: legacyStore.userId(),
            deviceId: legacyStore.deviceId(),
            restClient: MXRestClientStub(),
            getRoomAction: { _ in
                return nil
            })
        MXKeyProvider.sharedInstance().delegate = nil
        return machine
    }
    
    private func loadEncryptedEvent() throws -> MXEvent {
        guard let url = Bundle(for: Self.self).url(forResource: "archived_encrypted_event", withExtension: nil) else {
            throw Error.missingEvent
        }
        
        let data = try Data(contentsOf: url)
        guard let event = NSKeyedUnarchiver.unarchiveObject(with: data) as? MXEvent else {
            throw Error.missingEvent
        }
        return event
    }
    
    // MARK: - Tests
    
    func test_migratesAccountDetails() throws {
        let store = try LegacyRealmStore.load(account: .verified)
        let machine = try fullyMigratedOlmMachine(legacyStore: store)

        XCTAssertEqual(machine.userId, store.userId())
        XCTAssertEqual(machine.deviceId, store.deviceId())
        XCTAssertNotNil(machine.deviceCurve25519Key)
        XCTAssertEqual(machine.deviceCurve25519Key, store.account().identityKeys()[kMXKeyCurve25519Type] as? String)
        XCTAssertNotNil(machine.deviceEd25519Key)
        XCTAssertEqual(machine.deviceEd25519Key, store.account().identityKeys()[kMXKeyEd25519Type] as? String)
    }
    
    func test_canDecryptMegolmMessageAfterMigration() throws {
        // Load a previously archived and encrypted event
        let event = try loadEncryptedEvent()
        XCTAssertTrue(event.isEncrypted)
        XCTAssertEqual(event.content["algorithm"] as? String, kMXCryptoMegolmAlgorithm)
        XCTAssertNotNil(event.content["ciphertext"])

        // Migrate data to crypto v2
        let store = try LegacyRealmStore.load(account: .verified)
        let machine = try fullyMigratedOlmMachine(legacyStore: store)

        // Decrypt the event using crypto v2
        let decrypted = try machine.decryptRoomEvent(event)
        let result = try MXEventDecryptionResult(event: decrypted)
        let content = result.clearEvent["content"] as? [String: Any]

        // At this point we should be able to read back the original message after
        // having decrypted the event with room keys migrated earlier
        XCTAssertEqual(content?["body"] as? String, "Hi bob")
    }
    
    func test_notCrossSignedAfterMigration() throws {
        let store = try LegacyRealmStore.load(account: .unverified)
        let machine = try fullyMigratedOlmMachine(legacyStore: store)
        
        let crossSigningV2 = MXCrossSigningV2(crossSigning: machine, restClient: MXRestClientStub())
        XCTAssertFalse(crossSigningV2.canCrossSign)
        XCTAssertFalse(crossSigningV2.hasAllPrivateKeys)
    }
    
    func test_migratesCrossSigningStatus() throws {
        let store = try LegacyRealmStore.load(account: .verified)
        let machine = try fullyMigratedOlmMachine(legacyStore: store)
        
        let crossSigningV2 = MXCrossSigningV2(crossSigning: machine, restClient: MXRestClientStub())
        XCTAssertTrue(crossSigningV2.hasAllPrivateKeys)
    }
    
    func test_migratesRoomSettings() throws {
        let store = try LegacyRealmStore.load(account: .verified)
        let machine = try fullyMigratedOlmMachine(legacyStore: store)

        let settings = machine.roomSettings(roomId: LegacyRealmStore.Account.verified.roomId!)
        XCTAssertEqual(settings, .init(algorithm: .megolmV1AesSha2, onlyAllowTrustedDevices: true))
    }
    
    func test_migratesRoomSettingsInPartialMigration() throws {
        let store = try LegacyRealmStore.load(account: .verified)
        let machine = try partiallyMigratedOlmMachine(legacyStore: store)

        let settings = machine.roomSettings(roomId: LegacyRealmStore.Account.verified.roomId!)
        XCTAssertEqual(settings, .init(algorithm: .megolmV1AesSha2, onlyAllowTrustedDevices: true))
    }
    
    func test_migratesGlobalSettings() throws {
        let store1 = try LegacyRealmStore.load(account: .unverified)
        let machine1 = try fullyMigratedOlmMachine(legacyStore: store1)
        XCTAssertTrue(machine1.onlyAllowTrustedDevices)
        
        let store2 = try LegacyRealmStore.load(account: .verified)
        let machine2 = try fullyMigratedOlmMachine(legacyStore: store2)
        XCTAssertFalse(machine2.onlyAllowTrustedDevices)
    }
    
    func test_migratesGlobalSettingsInPartialMigration() throws {
        let store1 = try LegacyRealmStore.load(account: .unverified)
        let machine1 = try partiallyMigratedOlmMachine(legacyStore: store1)
        XCTAssertTrue(machine1.onlyAllowTrustedDevices)
        
        let store2 = try LegacyRealmStore.load(account: .verified)
        let machine2 = try partiallyMigratedOlmMachine(legacyStore: store2)
        XCTAssertFalse(machine2.onlyAllowTrustedDevices)
    }
}

extension MXCryptoMigrationV2UnitTests: Logger {
    func log(logLine: String) {
        MXLog.debug("[MXCryptoMigrationV2Tests]: \(logLine)")
    }
}

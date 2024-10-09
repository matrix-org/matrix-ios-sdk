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
@testable import MatrixSDK
import MatrixSDKCrypto

class MXCryptoKeyBackupEngineUnitTests: XCTestCase {
    actor DecryptorSpy: MXRoomEventDecrypting {
        func decrypt(events: [MXEvent]) -> [MXEventDecryptionResult] {
            return []
        }
        
        func handlePossibleRoomKeyEvent(_ event: MXEvent) {
        }
        
        var spySessionIds: [String] = []
        func retryUndecryptedEvents(sessionIds: [String]) {
            spySessionIds = sessionIds
        }
        
        func resetUndecryptedEvents() {
        }
    }
    
    var decryptor: DecryptorSpy!
    var backup: CryptoBackupStub!
    var engine: MXCryptoKeyBackupEngine!
    
    override func setUp() {
        decryptor = DecryptorSpy()
        backup = CryptoBackupStub()
        engine = MXCryptoKeyBackupEngine(backup: backup, roomEventDecryptor: decryptor)
    }
    
    func test_createsBackupKeyFromVersion() {
        let version = MXKeyBackupVersion.stub()
        
        do {
            try engine.enableBackup(with: version)
            
            XCTAssertEqual(backup.versionSpy, "3")
            XCTAssertEqual(backup.backupKeySpy?.publicKey, "ABC")
            XCTAssertEqual(backup.backupKeySpy?.passphraseInfo?.privateKeySalt, "salt")
            XCTAssertEqual(backup.backupKeySpy?.passphraseInfo?.privateKeyIterations, 10)
            XCTAssertEqual(backup.backupKeySpy?.signatures, [
                "bob": [
                    "ABC": "XYZ"
                ]
            ])
        } catch {
            XCTFail("Failed enabling backup - \(error)")
        }
    }
    
    func test_hasKeysToBackup() {
        backup.roomKeyCounts = .init(total: 0, backedUp: 0)
        XCTAssertFalse(engine.hasKeysToBackup())
        
        backup.roomKeyCounts = .init(total: 1, backedUp: 0)
        XCTAssertTrue(engine.hasKeysToBackup())
        
        backup.roomKeyCounts = .init(total: 2, backedUp: 3)
        XCTAssertFalse(engine.hasKeysToBackup())
    }
    
    func test_validPrivateKeyFromRecoveryKey_failsForInvalidPublicKey() {
        let key = BackupRecoveryKey()
        let invalidVersion = MXKeyBackupVersion.stub(
            publicKey: "invalid_key"
        )
        
        do {
            _ = try engine.validPrivateKey(forRecoveryKey: key.toBase58(), for: invalidVersion)
            XCTFail("Should not succeed")
        } catch MXCryptoKeyBackupEngine.Error.invalidPrivateKey {
            XCTAssert(true)
        } catch {
            XCTFail("Unknown error \(error)")
        }
    }
    
    func test_validPrivateKeyFromRecoveryKey_succeedsForInvalidPublicKey() {
        let key = BackupRecoveryKey()
        let invalidVersion = MXKeyBackupVersion.stub(
            publicKey: key.megolmV1PublicKey().publicKey
        )
        
        do {
            let privateKey = try engine.validPrivateKey(forRecoveryKey: key.toBase58(), for: invalidVersion)
            XCTAssertEqual(privateKey, try! MXRecoveryKey.decode(key.toBase58()))
        } catch {
            XCTFail("Unknown error \(error)")
        }
    }
}

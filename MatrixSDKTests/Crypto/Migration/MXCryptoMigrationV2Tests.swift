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
    var keyProvider: KeyProvider!
    
    override func setUp() {
        data = MatrixSDKTestsData()
        e2eData = MatrixSDKTestsE2EData(matrixSDKTestsData: data)
        
        keyProvider = KeyProvider()
        MXKeyProvider.sharedInstance().delegate = keyProvider
    }
    
    override func tearDown() {
        MXKeyProvider.sharedInstance().delegate = nil
    }
    
    func test_canDecryptMessageAfterMigratingLegacyCrypto() throws {
        e2eData.doE2ETestWithAliceAndBob(inARoom: self, cryptedBob: true, warnOnUnknowDevices: false) { aliceSession, bobSession, roomId, exp in
            guard
                let session = aliceSession,
                let userId = session.myUserId,
                let deviceId = session.myDeviceId,
                let store = session.legacyCrypto?.store,
                let room = session.room(withRoomId: roomId)
            else {
                XCTFail("Missing dependencies")
                return
            }
            
            var event: MXEvent!
            let clearTextMessage = "Hi bob"
            
            // Send clear text message to an E2E room
            room.sendTextMessage(clearTextMessage, localEcho: &event) { _ in
                
                // Erase cleartext and make sure the event was indeed encrypted
                event.setClearData(nil)
                XCTAssertTrue(event.isEncrypted)
                XCTAssertEqual(event.content["algorithm"] as? String, kMXCryptoMegolmAlgorithm)
                XCTAssertNotNil(event.content["ciphertext"])
                
                // Migrate data using crypto v2 migration and legacy store
                do {
                    let migration = MXCryptoMigrationV2(legacyStore: store)
                    try migration.migrateCrypto()
                } catch {
                    XCTFail("Cannot migrate - \(error)")
                }
                
                // Now instantiate crypto machine (crypto v2) that should be able to find
                // the migrated data and use it to decrypt the event
                do {
                    let url = try MXCryptoMachine.storeURL(for: userId)
                    let machine = try OlmMachine(
                        userId: userId,
                        deviceId: deviceId,
                        path: url.path,
                        passphrase: nil
                    )
                    
                    let decrypted = try machine.decryptRoomEvent(event: event.jsonString() ?? "", roomId: roomId!)
                    let result = try MXEventDecryptionResult(event: decrypted)
                    let content = result.clearEvent["content"] as? [String: Any]
                    
                    // At this point we should be able to read back the original message after
                    // having decrypted the event with room keys migrated earlier
                    XCTAssertEqual(content?["body"] as? String, clearTextMessage)
                    
                } catch {
                    XCTFail("Cannot decrypt - \(error)")
                }
                
                session.close()
                bobSession?.close()
                exp?.fulfill()
            }
        }
    }
}

#endif

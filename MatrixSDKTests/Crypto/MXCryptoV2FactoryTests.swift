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

class MXCryptoV2FactoryTests: XCTestCase {
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
    var factory: MXCryptoV2Factory!
    
    override func setUp() {
        data = .init()
        e2eData = .init(matrixSDKTestsData: data)
        factory = MXCryptoV2Factory()
        MXKeyProvider.sharedInstance().delegate = KeyProvider()
    }
    
    override func tearDown() {
        MXKeyProvider.sharedInstance().delegate = nil
    }
    
    private func buildCrypto(session: MXSession) async throws -> (MXCrypto?, Bool) {
        try await withCheckedThrowingContinuation { cont in
            var hasMigrated = false
            factory.buildCrypto(
                session: session) { _ in
                    hasMigrated = true
                } success: {
                    cont.resume(returning: ($0, hasMigrated))
                } failure: {
                    cont.resume(throwing: $0)
                }
        }
    }
    
    func test_doesNotMigrateNewUser() async throws {
        let env = try await e2eData.startE2ETest()
        let session = env.session
        
        // Simulating new user as one without a crypto database
        MXRealmCryptoStore.delete(with: session.credentials)
        
        // Build crypto and assert no migration has been performed
        let (crypto, hasMigrated) = try await buildCrypto(session: session)
        XCTAssertNotNil(crypto)
        XCTAssertFalse(hasMigrated)
        
        // Assert we have created legacy store (for remaining functionality) and marked it as deprecated
        let legacyStore = MXRealmCryptoStore.init(credentials: session.credentials)
        XCTAssertNotNil(legacyStore)
        XCTAssertEqual(legacyStore?.cryptoVersion, .versionLegacyDeprecated)
    }
    
    func test_migratesExistingUser() async throws {
        let env = try await e2eData.startE2ETest()
        let session = env.session
        let legacyStore = session.legacyCrypto?.store
        
        // Assert that we have a legacy store that has not yet been depreacted
        XCTAssertNotNil(legacyStore)
        XCTAssertEqual(legacyStore?.cryptoVersion, .version2)
        
        // Build crypto and assert migration has been performed
        let (crypto, hasMigrated) = try await buildCrypto(session: session)
        XCTAssertNotNil(crypto)
        XCTAssertTrue(hasMigrated)
        
        // Assert we still have legacy store but it is now marked as deprecated
        XCTAssertNotNil(legacyStore)
        XCTAssertEqual(legacyStore?.cryptoVersion, .versionLegacyDeprecated)
    }

    func test_doesNotMigrateDeprecatedStore() async throws {
        let env = try await e2eData.startE2ETest()
        let session = env.session
        
        // We set the legacy store as deprecated
        let legacyStore = session.legacyCrypto?.store
        XCTAssertNotNil(legacyStore)
        legacyStore?.cryptoVersion = .versionLegacyDeprecated
        
        // Build crypto and assert no migration has been performed
        let (crypto, hasMigrated) = try await buildCrypto(session: session)
        XCTAssertNotNil(crypto)
        XCTAssertFalse(hasMigrated)
        
        // Assert we still have legacy store which is still marked as deprecated
        XCTAssertNotNil(legacyStore)
        XCTAssertEqual(legacyStore?.cryptoVersion, .versionLegacyDeprecated)
    }
}

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
@testable import MatrixSDK

class MXCryptoV2FactoryUnitTests: XCTestCase {
    class MXSessionStub: MXSession {
        var stubbedCredentials: MXCredentials!
        override var credentials: MXCredentials! {
            return stubbedCredentials
        }
        
        override var myUserId: String! {
            return stubbedCredentials.userId
        }
        
        override var aggregations: MXAggregations! {
            return MXAggregations()
        }
        
        override var matrixRestClient: MXRestClient! {
            return MXRestClientStub(credentials: credentials)
        }
    }
    
    var factory: MXCryptoV2Factory!
    
    override func setUp() async throws {
        factory = MXCryptoV2Factory()
        MXKeyProvider.sharedInstance().delegate = MXKeyProviderStub()
    }
    
    override func tearDown() async throws {
        try LegacyRealmStore.deleteAllStores()
        MXKeyProvider.sharedInstance().delegate = nil
    }
    
    private func makeSession(userId: String) -> MXSession {
        let credentials = MXCredentials()
        credentials.userId = userId
        
        let session = MXSessionStub()
        session.stubbedCredentials = credentials
        return session
    }
    
    private func buildCrypto(account: LegacyRealmStore.Account) async throws -> (MXCrypto?, Bool) {
        let session = MXSessionStub()
        session.stubbedCredentials = account.credentials
        
        return try await withCheckedThrowingContinuation { cont in
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
    
    func test_hasCryptoData() throws {
        let alice = "Alice"
        let bob = "Bob"
        
        // Only create crypto data for alice
        let aliceUrl = try MXCryptoMachineStore.storeURL(for: alice)
        let data = "something".data(using: .ascii)!
        try data.write(to: aliceUrl)
        
        let aliceSession = makeSession(userId: alice)
        XCTAssertTrue(MXCryptoV2Factory.shared.hasCryptoData(for: aliceSession))
        
        let bobSession = makeSession(userId: bob)
        XCTAssertFalse(MXCryptoV2Factory.shared.hasCryptoData(for: bobSession))
    }
    
    func test_doesNotMigrateNewUser() async throws {
        // Build crypto and assert no migration has been performed
        let (crypto, hasMigrated) = try await buildCrypto(account: .version2)
        XCTAssertNotNil(crypto)
        XCTAssertFalse(hasMigrated)
    }
    
    func test_fullyMigratesLegacyUser() async throws {
        // Load the unmigrated legacy store
        let account = LegacyRealmStore.Account.version2
        XCTAssertFalse(LegacyRealmStore.hasData(for: account))
        let legacyStore = try LegacyRealmStore.load(account: account)
        XCTAssertTrue(LegacyRealmStore.hasData(for: account))
        XCTAssertEqual(legacyStore.cryptoVersion, .version2)
        
        // Build crypto and assert migration has been performed
        let (crypto, hasMigrated) = try await buildCrypto(account: account)
        XCTAssertNotNil(crypto)
        XCTAssertTrue(hasMigrated)

        // Assert that data for the legacy store has been removed
        XCTAssertFalse(LegacyRealmStore.hasData(for: account))
    }
    
    func test_migratesPartiallyMigratedUser() async throws {
        // Load partially deprecated legacy store
        let account = LegacyRealmStore.Account.deprecated1
        XCTAssertFalse(LegacyRealmStore.hasData(for: account))
        let legacyStore = try LegacyRealmStore.load(account: account)
        XCTAssertTrue(LegacyRealmStore.hasData(for: account))
        XCTAssertEqual(legacyStore.cryptoVersion, .deprecated1)
        
        // Build crypto and assert migration has been performed
        let (crypto, hasMigrated) = try await buildCrypto(account: account)
        XCTAssertNotNil(crypto)
        XCTAssertTrue(hasMigrated)

        // Assert that data for the legacy store has been removed
        XCTAssertFalse(LegacyRealmStore.hasData(for: account))
    }
    
    func test_doesNotMigrateDeprecatedStore() async throws {
        // Load fully deprecated legacy store
        let account = LegacyRealmStore.Account.deprecated3
        XCTAssertFalse(LegacyRealmStore.hasData(for: account))
        let legacyStore = try LegacyRealmStore.load(account: account)
        XCTAssertTrue(LegacyRealmStore.hasData(for: account))
        XCTAssertEqual(legacyStore.cryptoVersion, .deprecated3)
        
        // Build crypto and assert no migration has been performed
        let (crypto, hasMigrated) = try await buildCrypto(account: .deprecated3)
        XCTAssertNotNil(crypto)
        XCTAssertFalse(hasMigrated)

        // Assert that data for the legacy store has been removed
        XCTAssertFalse(LegacyRealmStore.hasData(for: account))
    }
}

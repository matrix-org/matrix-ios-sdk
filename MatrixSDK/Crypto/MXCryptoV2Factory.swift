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

@objc public class MXCryptoV2Factory: NSObject {
    enum Error: Swift.Error {
        case cryptoNotAvailable
        case storeNotAvailable
    }
    
    private let log = MXNamedLog(name: "MXCryptoV2Factory")
    private let sdkLog = MXCryptoMachineLogger()
    
    @objc public func buildCrypto(
        session: MXSession!,
        migrationProgress: ((Double) -> Void)?,
        success: @escaping (MXCrypto?) -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        guard
            let session = session,
            let restClient = session.matrixRestClient,
            let credentials = session.credentials,
            let userId = credentials.userId,
            let deviceId = credentials.deviceId
        else {
            log.failure("Missing required dependencies")
            failure(Error.cryptoNotAvailable)
            return
        }
        
        log.debug("Building crypto module")
        Task {
            do {
                let store = try await createOrOpenLegacyStore(credentials: credentials)
                try self.migrateIfNecessary(legacyStore: store) {
                    migrationProgress?($0)
                }
                
                let crypto = try await MXCryptoV2(
                    userId: userId,
                    deviceId: deviceId,
                    session: session,
                    restClient: restClient,
                    legacyStore: store
                )
                await MainActor.run {
                    success(crypto)
                }
            } catch {
                self.log.failure("Cannot create crypto")
                await MainActor.run {
                    failure(error)
                }
            }
        }
    }
    
    // A few features (e.g. global untrusted users blacklist) are not yet implemented in `MatrixSDKCrypto`
    // so they have to be stored in a legacy database. Will be moved to `MatrixSDKCrypto` eventually
    private func createOrOpenLegacyStore(credentials: MXCredentials) async throws -> MXCryptoStore {
        MXRealmCryptoStore.deleteReadonlyStore(with: credentials)
        
        if
            MXRealmCryptoStore.hasData(for: credentials),
            let legacyStore = MXRealmCryptoStore(credentials: credentials),
            legacyStore.account() != nil
        {
            log.debug("Legacy crypto store exists")
            return legacyStore
            
        } else {
            log.debug("Creating new legacy crypto store")
            
            MXRealmCryptoStore.delete(with: credentials)
            guard let legacyStore = MXRealmCryptoStore.createStore(with: credentials) else {
                log.failure("Cannot create legacy store")
                throw Error.storeNotAvailable
            }
            legacyStore.cryptoVersion = MXCryptoVersion.versionLegacyDeprecated
            
            log.debug("Legacy crypto store created")
            return legacyStore
        }
    }
    
    private func migrateIfNecessary(legacyStore: MXCryptoStore, updateProgress: @escaping (Double) -> Void) throws {
        guard legacyStore.cryptoVersion.rawValue < MXCryptoVersion.versionLegacyDeprecated.rawValue else {
            log.debug("Legacy crypto has already been deprecatd, no need to migrate")
            return
        }

        log.debug("Requires migration from legacy crypto")
        let migration = MXCryptoMigrationV2(legacyStore: legacyStore)
        try migration.migrateCrypto(updateProgress: updateProgress)
        
        log.debug("Marking legacy crypto as deprecated")
        legacyStore.cryptoVersion = MXCryptoVersion.versionLegacyDeprecated
    }
}

#endif

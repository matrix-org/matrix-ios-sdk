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

/// Delegate for migrating account data from legacy crypto to rust-based Crypto SDK
@objc public protocol MXCryptoV2MigrationDelegate {
    
    /// Flag indicating whether this account requires a re-verification after migrating to Crypto SDK
    ///
    /// This flag is set to true if the legacy account is considered verified but the rust account
    /// does not consider the migrated data secure enough, as it applies stricter security conditions.
    var needsVerificationUpgrade: Bool { get set }
}

@objc public class MXCryptoV2Factory: NSObject {
    enum Error: Swift.Error {
        case cryptoNotAvailable
    }
    
    @objc public static let shared = MXCryptoV2Factory()
    private let log = MXNamedLog(name: "MXCryptoV2Factory")
    
    private var lastDeprecatedVersion: MXCryptoVersion {
        .deprecated3
    }
    
    @objc public func hasCryptoData(for session: MXSession!) -> Bool {
        guard let userId = session?.myUserId else {
            log.error("Missing required dependencies")
            return false
        }
        
        do {
            let url = try MXCryptoMachineStore.storeURL(for: userId)
            return FileManager.default.fileExists(atPath: url.path)
        } catch {
            log.error("Failed creating url for user", context: error)
            return false
        }
    }
    
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
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            do {
                let crypto = try await MXCryptoV2(
                    userId: userId,
                    deviceId: deviceId,
                    session: session,
                    restClient: restClient
                )
                await MainActor.run {
                    success(crypto)
                }
            } catch {
                self.log.failure("Cannot create crypto", context: error)
                await MainActor.run {
                    failure(error)
                }
            }
        }
    }
}

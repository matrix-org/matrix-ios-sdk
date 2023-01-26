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

#if DEBUG

import OLMKit
import MatrixSDKCrypto

class MXCryptoMigrationV2: NSObject {
    private static let SessionBatchSize = 1000
    
    private let store: MXCryptoMigrationStore
    private let log = MXNamedLog(name: "MXCryptoMachineMigration")
    
    init(legacyStore: MXCryptoStore) {
        store = .init(legacyStore: legacyStore)
        super.init()
        OLMKit.sharedInstance().pickleKeyDelegate = self
    }
    
    func migrateCrypto(updateProgress: @escaping (Double) -> Void) throws {
        log.debug("Starting migration")
        MXCryptoMachineLogger.shared.log(logLine: "Starting logs")
        
        let startDate = Date()
        updateProgress(0)
        
        let key = pickleKey()
        let data = try store.extractData(with: key)
        let url = try MXCryptoMachineStore.storeURL(for: data.account.userId)
        
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        
        let details = """
        Migration summary
          - user id         : \(data.account.userId)
          - device id       : \(data.account.deviceId)
          - olm_sessions    : \(store.olmSessionCount)
          - megolm_sessions : \(store.megolmSessionCount)
          - backup_key      : \(data.backupRecoveryKey != nil ? "true" : "false")
          - cross_signing   : \(data.crossSigning.masterKey != nil ? "true" : "false")
          - tracked_users   : \(data.trackedUsers.count)
        """
        log.debug(details)
        
        try migrate(
            data: data,
            path: url.path,
            passphrase: nil,
            progressListener: self
        )
        
        log.debug("Migrating olm sessions in batches")
        
        // How much does migration of olm vs megolm sessions contribute to the overall progress
        let totalSessions = store.olmSessionCount + store.megolmSessionCount
        let olmToMegolmRatio = totalSessions > 0 ? Double(store.olmSessionCount)/Double(totalSessions) : 0
        
        store.extractSessions(with: key, batchSize: Self.SessionBatchSize) { [weak self] batch, progress in
            updateProgress(progress * olmToMegolmRatio)
            
            do {
                try self?.migrateSessions(
                    data: data,
                    sessions: batch,
                    url: url
                )
            } catch {
                self?.log.error("Error migrating some sessions", context: error)
            }
        }
        
        log.debug("Migrating megolm sessions in batches")
        
        store.extractGroupSessions(with: key, batchSize: Self.SessionBatchSize) { [weak self] batch, progress in
            updateProgress(olmToMegolmRatio + progress * (1 - olmToMegolmRatio))
            
            do {
                try self?.migrateSessions(
                    data: data,
                    inboundGroupSessions: batch,
                    url: url
                )
            } catch {
                self?.log.error("Error migrating some sessions", context: error)
            }
        }
        
        let duration = Date().timeIntervalSince(startDate) * 1000
        log.debug("Migration completed in \(duration) ms")
        updateProgress(1)
    }
    
    // To migrate sessions in batches and keep memory under control we are repeatedly calling `migrate`
    // function whilst only passing data for sessions and account, keeping the rest empty.
    // This API will be improved in `MatrixCryptoSDK` in the future.
    private func migrateSessions(
        data: MigrationData,
        sessions: [PickledSession] = [],
        inboundGroupSessions: [PickledInboundGroupSession] = [],
        url: URL
    ) throws {
        try migrate(
            data: .init(
                account: data.account,
                sessions: sessions,
                inboundGroupSessions: inboundGroupSessions,
                backupVersion: data.backupVersion,
                backupRecoveryKey: data.backupRecoveryKey,
                pickleKey: data.pickleKey,
                crossSigning: data.crossSigning,
                trackedUsers: data.trackedUsers
            ),
            path: url.path,
            passphrase: nil,
            progressListener: self
        )
    }
}

extension MXCryptoMigrationV2: OLMKitPickleKeyDelegate {
    public func pickleKey() -> Data {
        let key = MXKeyProvider.sharedInstance()
            .keyDataForData(
                ofType: MXCryptoOlmPickleKeyDataType,
                isMandatory: true,
                expectedKeyType: .rawData
            )
        
        guard let key = key as? MXRawDataKey else {
            log.failure("Wrong key")
            return Data()
        }
        
        return key.key
    }
}

extension MXCryptoMigrationV2: ProgressListener {
    func onProgress(progress: Int32, total: Int32) {
        // Progress loggged manually
    }
}

#endif

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
@_implementationOnly import OLMKit
@_implementationOnly import MatrixSDKCrypto

class MXCryptoMigrationV2: NSObject {
    enum Error: Swift.Error {
        case missingCredentials
        case unknownPickleKey
    }
    
    private static let SessionBatchSize = 1000
    
    private let legacyDevice: MXOlmDevice
    private let store: MXCryptoMigrationStore
    private let log = MXNamedLog(name: "MXCryptoMachineMigration")
    
    init(legacyStore: MXCryptoStore) {
        MXCryptoSDKLogger.shared.log(logLine: "Starting logs")
        
        // We need to create legacy OlmDevice which sets itself internally as pickle key delegate
        // Once established we can get the pickleKey from OLMKit which is used to decrypt and migrate
        // the legacy store data
        legacyDevice = MXOlmDevice(store: legacyStore)
        store = .init(legacyStore: legacyStore)
    }
    
    func migrateAllData(updateProgress: @escaping (Double) -> Void) throws {
        log.debug("Starting migration")
        
        let startDate = Date()
        updateProgress(0)
        
        let pickleKey = try legacyPickleKey()
        let data = try store.extractData(with: pickleKey)
        
        let url = try MXCryptoMachineStore.storeURL(for: data.account.userId)
        let passphrase = try MXCryptoMachineStore.storePassphrase()
        
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        
        let details = """
        Migration summary
          - user id          : \(data.account.userId)
          - device id        : \(data.account.deviceId)
          - olm_sessions     : \(store.olmSessionCount)
          - megolm_sessions  : \(store.megolmSessionCount)
          - backup_key       : \(data.backupRecoveryKey != nil ? "true" : "false")
          - master_key       : \(data.crossSigning.masterKey != nil ? "true" : "false")
          - user_signing_key : \(data.crossSigning.userSigningKey != nil ? "true" : "false")
          - self_signing_key : \(data.crossSigning.selfSigningKey != nil ? "true" : "false")
          - tracked_users    : \(data.trackedUsers.count)
          - room_settings    : \(data.roomSettings.count)
          - global_settings  : \(store.globalSettings)
        """
        log.debug(details)
        
        try migrate(
            data: data,
            path: url.path,
            passphrase: passphrase,
            progressListener: self
        )
        
        log.debug("Migrating olm sessions in batches")
        
        // How much does migration of olm vs megolm sessions contribute to the overall progress
        let totalSessions = store.olmSessionCount + store.megolmSessionCount
        let olmToMegolmRatio = totalSessions > 0 ? Double(store.olmSessionCount)/Double(totalSessions) : 0
        
        store.extractSessions(with: pickleKey, batchSize: Self.SessionBatchSize) { [weak self] batch, progress in
            updateProgress(progress * olmToMegolmRatio)
            
            do {
                try self?.migrateSessionsBatch(
                    data: data,
                    sessions: batch,
                    url: url,
                    passphrase: passphrase
                )
            } catch {
                self?.log.error("Error migrating some sessions", context: error)
            }
        }
        
        log.debug("Migrating megolm sessions in batches")
        
        store.extractGroupSessions(with: pickleKey, batchSize: Self.SessionBatchSize) { [weak self] batch, progress in
            updateProgress(olmToMegolmRatio + progress * (1 - olmToMegolmRatio))
            
            do {
                try self?.migrateSessionsBatch(
                    data: data,
                    inboundGroupSessions: batch,
                    url: url,
                    passphrase: passphrase
                )
            } catch {
                self?.log.error("Error migrating some sessions", context: error)
            }
        }
        
        log.debug("Migrating global settings")
        try migrateGlobalSettings(
            userId: data.account.userId,
            deviceId: data.account.deviceId,
            url: url,
            passphrase: passphrase
        )
        
        let duration = Date().timeIntervalSince(startDate) * 1000
        log.debug("Migration completed in \(duration) ms")
        updateProgress(1)
    }
    
    func migrateRoomAndGlobalSettingsOnly(updateProgress: @escaping (Double) -> Void) throws {
        guard let userId = store.userId, let deviceId = store.deviceId else {
            throw Error.missingCredentials
        }
        
        let url = try MXCryptoMachineStore.storeURL(for: userId)
        let passphrase = try MXCryptoMachineStore.storePassphrase()
        let settings = store.extractRoomSettings()
        
        let details = """
        Settings migration summary
          - user id         : \(userId)
          - device id       : \(deviceId)
          - room_settings   : \(settings.count)
          - global_settings : \(store.globalSettings)
        """
        log.debug(details)
        updateProgress(0)
        
        try migrateRoomSettings(
            roomSettings: settings,
            path: url.path,
            passphrase: passphrase
        )
        
        log.debug("Migrating global settings")
        try migrateGlobalSettings(
            userId: userId,
            deviceId: deviceId,
            url: url,
            passphrase: passphrase
        )
        
        log.debug("Migration completed")
        updateProgress(1)
    }
    
    private func legacyPickleKey() throws -> Data {
        guard let key = OLMKit.sharedInstance().pickleKeyDelegate?.pickleKey() else {
            throw Error.unknownPickleKey
        }
        return key
    }
    
    private func migrateSessionsBatch(
        data: MigrationData,
        sessions: [PickledSession] = [],
        inboundGroupSessions: [PickledInboundGroupSession] = [],
        url: URL,
        passphrase: String
    ) throws {
        try migrateSessions(
            data: .init(
                userId: data.account.userId,
                deviceId: data.account.deviceId,
                curve25519Key: legacyDevice.deviceCurve25519Key,
                ed25519Key: legacyDevice.deviceEd25519Key,
                sessions: sessions,
                inboundGroupSessions: inboundGroupSessions,
                pickleKey: data.pickleKey
            ),
            path: url.path,
            passphrase: passphrase,
            progressListener: self
        )
    }
    
    private func migrateGlobalSettings(
        userId: String,
        deviceId: String,
        url: URL,
        passphrase: String
    ) throws {
        let machine = try OlmMachine(
            userId: userId,
            deviceId: deviceId,
            path: url.path,
            passphrase: passphrase
        )
        
        let onlyTrusted = store.globalSettings.onlyAllowTrustedDevices
        try machine.setOnlyAllowTrustedDevices(onlyAllowTrustedDevices: onlyTrusted)
    }
}

extension MXCryptoMigrationV2: ProgressListener {
    func onProgress(progress: Int32, total: Int32) {
        // Progress loggged manually
    }
}

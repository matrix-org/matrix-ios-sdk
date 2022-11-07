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

import MatrixSDKCrypto

class MXCryptoKeyBackupEngine: NSObject, MXKeyBackupEngine {
    enum Error: Swift.Error {
        case unknownBackupVersion
        case invalidData
        case invalidPrivateKey
        case algorithmNotSupported(String)
    }
    
    var enabled: Bool {
        return backup.isBackupEnabled
    }
    
    var version: String? {
        return backup.backupKeys?.backupVersion()
    }
    
    private var recoveryKey: BackupRecoveryKey? {
        return backup.backupKeys?.recoveryKey()
    }
    
    private let backup: MXCryptoBackup
    private let roomEventDecryptor: MXRoomEventDecrypting
    private let log = MXNamedLog(name: "MXCryptoKeyBackupEngine")
    
    init(backup: MXCryptoBackup, roomEventDecryptor: MXRoomEventDecrypting) {
        self.backup = backup
        self.roomEventDecryptor = roomEventDecryptor
    }
    
    // MARK: - Enable / Disable engine
    
    func enableBackup(with keyBackupVersion: MXKeyBackupVersion) throws {
        log.debug("->")
        
        guard let version = keyBackupVersion.version else {
            log.error("Unknown backup version")
            throw Error.unknownBackupVersion
        }
        
        let key = try MegolmV1BackupKey(keyBackupVersion: keyBackupVersion)
        try backup.enableBackup(key: key, version: version)
        log.debug("Backup enabled")
    }
    
    func disableBackup() {
        guard enabled else {
            return
        }
        
        log.debug("->")
        backup.disableBackup()
    }
    
    // MARK: - Private / Recovery key management
    
    func privateKey() -> Data? {
        guard let recoveryKey = recoveryKey?.toBase58() else {
            log.debug("No known backup key")
            return nil
        }
        do {
            return try MXRecoveryKey.decode(recoveryKey)
        } catch {
            log.error("Cannot create private key from recovery key", context: error)
            return nil
        }
    }
    
    func savePrivateKey(_ privateKey: Data, version: String) {
        let recoveryKey = MXRecoveryKey.encode(privateKey)
        do {
            let key = try BackupRecoveryKey.fromBase58(key: recoveryKey)
            try backup.saveRecoveryKey(key: key, version: version)
            log.debug("New private key saved")
        } catch {
            log.error("Cannot save private key", context: error)
        }
    }
    
    func hasValidPrivateKey() -> Bool {
        return recoveryKey != nil
    }
    
    func hasValidPrivateKey(for keyBackupVersion: MXKeyBackupVersion) -> Bool {
        guard let recoveryKey = recoveryKey else {
            log.debug("Not recovery key")
            return false
        }
        return recoveryKey.megolmV1PublicKey().publicKey == publicKey(for: keyBackupVersion)
    }
    
    func validPrivateKey(forRecoveryKey recoveryKey: String, for keyBackupVersion: MXKeyBackupVersion) throws -> Data {
        let key = try BackupRecoveryKey.fromBase58(key: recoveryKey)
        guard key.megolmV1PublicKey().publicKey == publicKey(for: keyBackupVersion) else {
            throw Error.invalidPrivateKey
        }
        
        let privateKey = try MXRecoveryKey.decode(recoveryKey)
        log.debug("Created valid private key from recovery key")
        return privateKey
    }
    
    func recoveryKey(fromPassword password: String, in keyBackupVersion: MXKeyBackupVersion) throws -> String {
        guard
            let authData = MXCurve25519BackupAuthData(fromJSON: keyBackupVersion.authData),
            let salt = authData.privateKeySalt
        else {
            log.error("Invalid auth data")
            throw Error.invalidData
        }

        let key = BackupRecoveryKey.fromPassphrase(
            passphrase: password,
            salt: salt,
            rounds: Int32(authData.privateKeyIterations)
        )
        
        log.debug("Created recovery key from password")
        return key.toBase58()
    }
    
    // MARK: - Backup versions
    
    func prepareKeyBackupVersion(
        withPassword password: String?,
        algorithm: String?,
        success: @escaping (MXMegolmBackupCreationInfo) -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.debug("->")
        
        guard algorithm == nil || algorithm == kMXCryptoCurve25519KeyBackupAlgorithm else {
            log.error("Algorithm not supported")
            failure(Error.algorithmNotSupported(algorithm!))
            return
        }

        let key = password != nil ? BackupRecoveryKey.newFromPassphrase(passphrase: password!) : BackupRecoveryKey()
        let publicKey = key.megolmV1PublicKey()

        let authData = MXCurve25519BackupAuthData()
        authData.publicKey = publicKey.publicKey
        if let info = publicKey.passphraseInfo {
            authData.privateKeySalt = info.privateKeySalt
            authData.privateKeyIterations = UInt(info.privateKeyIterations)
        }

        do {
            authData.signatures = try backup.sign(object: authData.signalableJSONDictionary)
        } catch {
            log.error("Cannot create signatures", context: error)
        }

        let info = MXMegolmBackupCreationInfo()
        info.algorithm = publicKey.backupAlgorithm
        info.authData = authData
        info.recoveryKey = key.toBase58()

        log.debug("Key backup version info is ready")
        success(info)
    }
    
    func trust(for keyBackupVersion: MXKeyBackupVersion) -> MXKeyBackupVersionTrust {
        let trust = MXKeyBackupVersionTrust()
        trust.usable = backup.verifyBackup(version: keyBackupVersion)
        log.debug("Key backup version is \(trust.usable ? "trusted" : "untrusted")")
        return trust
    }
    
    func authData(from keyBackupVersion: MXKeyBackupVersion) throws -> MXBaseKeyBackupAuthData {
        guard let data = MXCurve25519BackupAuthData(fromJSON: keyBackupVersion.authData) else {
            throw Error.invalidData
        }
        return data
    }
    
    func signObject(_ object: [AnyHashable : Any]) -> [AnyHashable : Any] {
        do {
            return try backup.sign(object: object)
        } catch {
            log.error("Failed signing object", context: error)
            return [:]
        }
    }
    
    // MARK: - Backup keys
    
    func hasKeysToBackup() -> Bool {
        guard let counts = backup.roomKeyCounts else {
            return false
        }
        return counts.total > counts.backedUp
    }
    
    func backupProgress() -> Progress {
        guard let counts = backup.roomKeyCounts else {
            return Progress()
        }
        
        let progress = Progress(totalUnitCount: counts.total)
        progress.completedUnitCount = counts.backedUp
        
        log.debug("Backed up \(progress.completedUnitCount) out of \(progress.totalUnitCount) keys")
        return progress
    }
    
    func backupKeys(
        success: @escaping () -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.debug("->")
        Task {
            do {
                try await backup.backupRoomKeys()
                await MainActor.run {
                    log.debug("Successfully backed up keys")
                    success()
                }
            } catch {
                await MainActor.run {
                    log.error("Failed backing up keys", context: error)
                    failure(error)
                }
            }
        }
    }
    
    func importKeys(
        with keysBackupData: MXKeysBackupData,
        privateKey: Data,
        keyBackupVersion: MXKeyBackupVersion,
        success: @escaping (UInt, UInt) -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        Task(priority: .medium) {
            
            let count = keysBackupData.rooms
                .map { roomId, room in
                    room.sessions.count
                }
                .reduce(0, +)
            
            log.debug("Importing \(count) encrypted sessions")
            
            let recoveryKey: BackupRecoveryKey
            do {
                let key = MXRecoveryKey.encode(privateKey)
                recoveryKey = try BackupRecoveryKey.fromBase58(key: key)
            } catch {
                log.error("Failed creating recovery key")
                failure(Error.invalidPrivateKey)
                return
            }
            
            let date1 = Date()
            
            let sessions = keysBackupData.rooms
                .flatMap { roomId, room in
                    room.sessions
                        .compactMap { sessionId, keyBackup in
                            decrypt(
                                keyBackupData:keyBackup,
                                keyBackupVersion: keyBackupVersion,
                                recoveryKey: recoveryKey,
                                forSession: sessionId,
                                inRoom: roomId
                            )
                        }
                }
            
            let duration1 = Date().timeIntervalSince(date1) * 1000
            log.debug("Decrypted \(sessions.count) sessions in \(duration1) ms")
            
            let date2 = Date()
            
            do {
                let result = try backup.importDecryptedKeys(roomKeys: sessions, progressListener: self)
                await roomEventDecryptor.retryAllUndecryptedEvents()
                
                let duration2 = Date().timeIntervalSince(date2) * 1000
                log.debug("Successfully imported \(result.imported) out of \(result.total) sessions in \(duration2) ms")
                
                await MainActor.run {
                    success(UInt(result.total), UInt(result.imported))
                }
            } catch {
                log.error("Failed importing sessions", context: error)
                await MainActor.run {
                    failure(error)
                }
            }
        }
    }
    
    private func decrypt(
        keyBackupData: MXKeyBackupData,
        keyBackupVersion: MXKeyBackupVersion,
        recoveryKey: BackupRecoveryKey,
        forSession sessionId: String,
        inRoom roomId: String
    ) -> MXMegolmSessionData? {
        guard
            let ciphertext = keyBackupData.sessionData["ciphertext"] as? String,
            let mac = keyBackupData.sessionData["mac"] as? String,
            let ephemeral = keyBackupData.sessionData["ephemeral"] as? String
        else {
            log.error("Missing session data properties")
            return nil
        }
        
        let plaintext: String
        do {
            plaintext = try recoveryKey.decryptV1(
                ephemeralKey: ephemeral,
                mac: mac,
                ciphertext: ciphertext
            )
        } catch {
            log.error("Failed decrypting backup data", context: error)
            return nil
        }
        
        guard
            let json = MXTools.deserialiseJSONString(plaintext) as? [AnyHashable: Any],
            let data = MXMegolmSessionData(fromJSON: json)
        else {
            log.error("Failed serializing data")
            return nil
        }
        
        data.sessionId = sessionId
        data.roomId = roomId
        data.isUntrusted = true // Asymmetric backups are untrusted by default
        return data
    }
    
    // MARK: - Manual export / import
    
    func exportRoomKeys(passphrase: String) throws -> Data {
        return try backup.exportRoomKeys(passphrase: passphrase)
    }
    
    func importRoomKeys(_ data: Data, passphrase: String) async throws -> KeysImportResult {
        let result = try backup.importRoomKeys(data, passphrase: passphrase, progressListener: self)
        await roomEventDecryptor.retryAllUndecryptedEvents()
        return result
    }
    
    // MARK: - Private
    
    func publicKey(for keyBackupVersion: MXKeyBackupVersion) -> String? {
        guard let authData = MXCurve25519BackupAuthData(fromJSON: keyBackupVersion.authData) else {
            log.error("Cannot create auth data for backup version")
            return nil
        }
        return authData.publicKey
    }
}

extension MXCryptoKeyBackupEngine: ProgressListener {
    func onProgress(progress: Int32, total: Int32) {
        log.debug("Backup / export progress \(progress) of \(total) total")
    }
}

extension MegolmV1BackupKey {
    enum Error: Swift.Error {
        case invalidData
    }
    
    init(keyBackupVersion: MXKeyBackupVersion) throws {
        guard
            let authData = MXCurve25519BackupAuthData(fromJSON: keyBackupVersion.authData),
            let signatures = authData.signatures as? [String: [String: String]]
        else {
            throw Error.invalidData
        }
        
        let info: PassphraseInfo?
        if let salt = authData.privateKeySalt {
            info = PassphraseInfo(
                privateKeySalt: salt,
                privateKeyIterations: Int32(authData.privateKeyIterations)
            )
        } else {
            info = nil
        }
        
        self.init(
            publicKey: authData.publicKey,
            signatures: signatures,
            passphraseInfo: info,
            backupAlgorithm: keyBackupVersion.algorithm
        )
    }
}

#endif

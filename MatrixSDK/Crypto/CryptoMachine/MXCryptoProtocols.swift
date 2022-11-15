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

/// A set of protocols defining the functionality in `MatrixSDKCrypto` and separating them into logical units

/// Cryptographic identity of the currently signed-in user
protocol MXCryptoIdentity {
    var userId: String { get }
    var deviceId: String { get }
    var deviceCurve25519Key: String? { get }
    var deviceEd25519Key: String? { get }
}

/// Handler for cryptographic events in the sync loop
protocol MXCryptoSyncing: MXCryptoIdentity {
    func handleSyncResponse(
        toDevice: MXToDeviceSyncResponse?,
        deviceLists: MXDeviceListResponse?,
        deviceOneTimeKeysCounts: [String: NSNumber],
        unusedFallbackKeys: [String]?
    ) throws -> MXToDeviceSyncResponse
    
    func processOutgoingRequests() async throws
}

/// Source of user devices and their cryptographic trust status
protocol MXCryptoDevicesSource: MXCryptoIdentity {
    func device(userId: String, deviceId: String) -> Device?
    func devices(userId: String) -> [Device]
}

/// Source of user identities and their cryptographic trust status
protocol MXCryptoUserIdentitySource: MXCryptoIdentity {
    func userIdentity(userId: String) -> UserIdentity?
    func isUserVerified(userId: String) -> Bool
    func isUserTracked(userId: String) -> Bool
    func downloadKeys(users: [String]) async throws
    func verifyUser(userId: String) async throws
    func verifyDevice(userId: String, deviceId: String) async throws
    func setLocalTrust(userId: String, deviceId: String, trust: LocalTrust) throws
}

/// Room event encryption
protocol MXCryptoRoomEventEncrypting: MXCryptoIdentity {
    func shareRoomKeysIfNecessary(roomId: String, users: [String], settings: EncryptionSettings) async throws
    func encryptRoomEvent(content: [AnyHashable: Any], roomId: String, eventType: String) throws -> [String: Any]
    func discardRoomKey(roomId: String)
}

/// Room event decryption
protocol MXCryptoRoomEventDecrypting: MXCryptoIdentity {
    func decryptRoomEvent(_ event: MXEvent) throws -> DecryptedEvent
    func requestRoomKey(event: MXEvent) async throws
}

/// Cross-signing functionality
protocol MXCryptoCrossSigning: MXCryptoUserIdentitySource {
    func crossSigningStatus() -> CrossSigningStatus
    func bootstrapCrossSigning(authParams: [AnyHashable: Any]) async throws
    func exportCrossSigningKeys() -> CrossSigningKeyExport?
    func importCrossSigningKeys(export: CrossSigningKeyExport)
}

/// Lifecycle of verification request
protocol MXCryptoVerificationRequesting: MXCryptoIdentity {
    func receiveUnencryptedVerificationEvent(event: MXEvent, roomId: String)
    func requestSelfVerification(methods: [String]) async throws -> VerificationRequest
    func requestVerification(userId: String, roomId: String, methods: [String]) async throws -> VerificationRequest
    func requestVerification(userId: String, deviceId: String, methods: [String]) async throws -> VerificationRequest
    func verificationRequests(userId: String) -> [VerificationRequest]
    func verificationRequest(userId: String, flowId: String) -> VerificationRequest?
    func acceptVerificationRequest(userId: String, flowId: String, methods: [String]) async throws
    func cancelVerification(userId: String, flowId: String, cancelCode: String) async throws
}

/// Lifecycle of verification transaction
protocol MXCryptoVerifying: MXCryptoIdentity {
    func verification(userId: String, flowId: String) -> Verification?
    func confirmVerification(userId: String, flowId: String) async throws
    func cancelVerification(userId: String, flowId: String, cancelCode: String) async throws
}

/// Lifecycle of SAS-specific verification transaction
protocol MXCryptoSASVerifying: MXCryptoVerifying {
    func startSasVerification(userId: String, flowId: String) async throws -> Sas
    func acceptSasVerification(userId: String, flowId: String) async throws
    func emojiIndexes(sas: Sas) throws -> [Int]
    func sasDecimals(sas: Sas) throws -> [Int]
}

/// Lifecycle of QR code-specific verification transaction
protocol MXCryptoQRCodeVerifying: MXCryptoVerifying {
    func startQrVerification(userId: String, flowId: String) throws -> QrCode
    func scanQrCode(userId: String, flowId: String, data: Data) async throws -> QrCode
    func generateQrCode(userId: String, flowId: String) throws -> Data
}

/// Room keys backup functionality
protocol MXCryptoBackup {
    var isBackupEnabled: Bool { get }
    var backupKeys: BackupKeys? { get }
    var roomKeyCounts: RoomKeyCounts? { get }
    
    func enableBackup(key: MegolmV1BackupKey, version: String) throws
    func disableBackup()
    func saveRecoveryKey(key: BackupRecoveryKey, version: String?) throws
    
    func verifyBackup(version: MXKeyBackupVersion) -> Bool
    func sign(object: [AnyHashable: Any]) throws -> [String: [String: String]]
    
    func backupRoomKeys() async throws
    func importDecryptedKeys(roomKeys: [MXMegolmSessionData], progressListener: ProgressListener) throws -> KeysImportResult
    
    func exportRoomKeys(passphrase: String) throws -> Data
    func importRoomKeys(_ data: Data, passphrase: String, progressListener: ProgressListener) throws -> KeysImportResult
}

#endif

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
    
    @MainActor
    func handleSyncResponse(
        toDevice: MXToDeviceSyncResponse?,
        deviceLists: MXDeviceListResponse?,
        deviceOneTimeKeysCounts: [String: NSNumber],
        unusedFallbackKeys: [String]?,
        nextBatchToken: String
    ) throws -> MXToDeviceSyncResponse
    
    func processOutgoingRequests() async throws
    
    func downloadKeysIfNecessary(users: [String]) async throws
    
    @available(*, deprecated, message: "The application should not manually force reload keys, use `downloadKeysIfNecessary` instead")
    func reloadKeys(users: [String]) async throws
}

/// Source of user devices and their cryptographic trust status
protocol MXCryptoDevicesSource: MXCryptoIdentity {
    func device(userId: String, deviceId: String) -> Device?
    func devices(userId: String) -> [Device]
    func dehydratedDevices() -> DehydratedDevicesProtocol
}

/// Source of user identities and their cryptographic trust status
protocol MXCryptoUserIdentitySource: MXCryptoIdentity {
    func userIdentity(userId: String) -> UserIdentity?
    func isUserVerified(userId: String) -> Bool
    func verifyUser(userId: String) async throws
    func verifyDevice(userId: String, deviceId: String) async throws
    func setLocalTrust(userId: String, deviceId: String, trust: LocalTrust) throws
}

/// Room event encryption
protocol MXCryptoRoomEventEncrypting: MXCryptoIdentity {
    var onlyAllowTrustedDevices: Bool { get set }
    
    func isUserTracked(userId: String) -> Bool
    func updateTrackedUsers(_ users: [String])
    func roomSettings(roomId: String) -> RoomSettings?
    func setRoomAlgorithm(roomId: String, algorithm: EventEncryptionAlgorithm) throws
    func setOnlyAllowTrustedDevices(for roomId: String, onlyAllowTrustedDevices: Bool) throws
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
protocol MXCryptoCrossSigning: MXCryptoUserIdentitySource, MXCryptoDevicesSource {
    func refreshCrossSigningStatus() async throws
    func crossSigningStatus() -> CrossSigningStatus
    func bootstrapCrossSigning(authParams: [AnyHashable: Any]) async throws
    func exportCrossSigningKeys() -> CrossSigningKeyExport?
    func importCrossSigningKeys(export: CrossSigningKeyExport) throws
    
    func queryMissingSecretsFromOtherSessions() async throws
}

/// Verification functionality
protocol MXCryptoVerifying: MXCryptoIdentity {
    func downloadKeysIfNecessary(users: [String]) async throws
    func receiveVerificationEvent(event: MXEvent, roomId: String) async throws
    func requestSelfVerification(methods: [String]) async throws -> VerificationRequestProtocol
    func requestVerification(userId: String, roomId: String, methods: [String]) async throws -> VerificationRequestProtocol
    func requestVerification(userId: String, deviceId: String, methods: [String]) async throws -> VerificationRequestProtocol
    func verificationRequests(userId: String) -> [VerificationRequestProtocol]
    func verificationRequest(userId: String, flowId: String) -> VerificationRequestProtocol?
    func verification(userId: String, flowId: String) -> MXVerification?
    func handleOutgoingVerificationRequest(_ request: OutgoingVerificationRequest) async throws
    func handleVerificationConfirmation(_ result: ConfirmVerificationResult) async throws
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

/// Wrapper around `MatrixSDKCrypto`'s `Verification`, modelled as an exhaustive enum
///
/// Note: this is not currently possible to do automatically with uniffi
enum MXVerification {
    case sas(SasProtocol)
    case qrCode(QrCodeProtocol)
}


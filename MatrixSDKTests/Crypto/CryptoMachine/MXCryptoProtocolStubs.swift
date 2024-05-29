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
@testable import MatrixSDK
@testable import MatrixSDKCrypto

class CryptoIdentityStub: MXCryptoIdentity {
    var userId: String = "Alice"
    var deviceId: String = "ABCD"
    
    var deviceCurve25519Key: String? {
        return nil
    }
    
    var deviceEd25519Key: String? {
        return nil
    }
}

class DevicesSourceStub: CryptoIdentityStub, MXCryptoDevicesSource {
    var devices = [String: [String: Device]]()
    
    func device(userId: String, deviceId: String) -> Device? {
        return devices[userId]?[deviceId]
    }
    
    func devices(userId: String) -> [Device] {
        return devices[userId]?.map { $0.value } ?? []
    }
    
    func dehydratedDevices() -> DehydratedDevicesProtocol {
        fatalError()
    }
}

class UserIdentitySourceStub: CryptoIdentityStub, MXCryptoUserIdentitySource {
    var identities = [String: UserIdentity]()
    func userIdentity(userId: String) -> UserIdentity? {
        return identities[userId]
    }
    
    var verification = [String: Bool]()
    func isUserVerified(userId: String) -> Bool {
        return verification[userId] ?? false
    }
    
    func isUserTracked(userId: String) -> Bool {
        return true
    }
    
    func downloadKeys(users: [String]) async throws {
    }
    
    func verifyUser(userId: String) async throws {
    }
    
    func verifyDevice(userId: String, deviceId: String) async throws {
    }
    
    func setLocalTrust(userId: String, deviceId: String, trust: LocalTrust) throws {
    }
}

class CryptoCrossSigningStub: CryptoIdentityStub, MXCryptoCrossSigning {
    enum Error: Swift.Error {
        case deviceMissing
    }
    
    var stubbedStatus = CrossSigningStatus(
        hasMaster: false,
        hasSelfSigning: false,
        hasUserSigning: false
    )
    
    func refreshCrossSigningStatus() async throws {
    }
    
    func crossSigningStatus() -> CrossSigningStatus {
        return stubbedStatus
    }
    
    var spyAuthParams: [AnyHashable: Any]?
    func bootstrapCrossSigning(authParams: [AnyHashable : Any]) async throws {
        self.spyAuthParams = authParams
    }
    
    func exportCrossSigningKeys() -> CrossSigningKeyExport? {
        return nil
    }
    
    func importCrossSigningKeys(export: CrossSigningKeyExport) {
    }
    
    var stubbedIdentities = [String: UserIdentity]()
    func userIdentity(userId: String) -> UserIdentity? {
        stubbedIdentities[userId]
    }
    
    var stubbedVerifiedUsers = Set<String>()
    func isUserVerified(userId: String) -> Bool {
        return stubbedVerifiedUsers.contains(userId)
    }
    
    func isUserTracked(userId: String) -> Bool {
        return true
    }
    
    func downloadKeys(users: [String]) async throws {
    }
    
    func verifyUser(userId: String) async throws {
    }
    
    var verifiedDevicesSpy = Set<String>()
    func verifyDevice(userId: String, deviceId: String) async throws {
        guard let device = devices[userId]?[deviceId] else {
            throw Error.deviceMissing
        }
        
        verifiedDevicesSpy.insert(deviceId)
        
        devices[userId]?[deviceId] = Device(
            userId: device.userId,
            deviceId: device.deviceId,
            keys: device.keys,
            algorithms: device.algorithms,
            displayName: device.displayName,
            isBlocked: device.isBlocked,
            locallyTrusted: device.locallyTrusted,
            // Modify cross signing trusted
            crossSigningTrusted: true,
            firstTimeSeenTs: 0,
            dehydrated: false
        )
    }
    
    func setLocalTrust(userId: String, deviceId: String, trust: LocalTrust) throws {
    }
    
    var devices = [String: [String: Device]]()
    
    func device(userId: String, deviceId: String) -> Device? {
        return devices[userId]?[deviceId]
    }
    
    func devices(userId: String) -> [Device] {
        return devices[userId]?.map { $0.value } ?? []
    }
    
    func dehydratedDevices() -> DehydratedDevicesProtocol {
        fatalError()
    }
    
    func queryMissingSecretsFromOtherSessions() async throws {
        
    }
}

class CryptoVerificationStub: CryptoIdentityStub {
    var stubbedTransactions = [String: MXVerification]()
}

extension CryptoVerificationStub: MXCryptoVerifying {
    func downloadKeysIfNecessary(users: [String]) async throws {
    }
    
    func receiveVerificationEvent(event: MXEvent, roomId: String) {
    }
    
    func requestSelfVerification(methods: [String]) async throws -> VerificationRequestProtocol {
        VerificationRequestStub(ourMethods: methods)
    }
    
    func requestVerification(userId: String, roomId: String, methods: [String]) async throws -> VerificationRequestProtocol {
        VerificationRequestStub(otherUserId: userId, roomId: roomId, ourMethods: methods)
    }
    
    func requestVerification(userId: String, deviceId: String, methods: [String]) async throws -> VerificationRequestProtocol {
        VerificationRequestStub(otherUserId: userId, otherDeviceId: deviceId, ourMethods: methods)
    }
    
    func verificationRequests(userId: String) -> [VerificationRequestProtocol] {
        []
    }
    
    func verificationRequest(userId: String, flowId: String) -> VerificationRequestProtocol? {
        nil
    }
    
    func verification(userId: String, flowId: String) -> MXVerification? {
        stubbedTransactions[flowId]
    }
    
    func handleOutgoingVerificationRequest(_ request: OutgoingVerificationRequest) async throws {
    }
    
    func handleVerificationConfirmation(_ result: ConfirmVerificationResult) async throws {
    }
}

class CryptoBackupStub: MXCryptoBackup {
    var isBackupEnabled: Bool = false
    var backupKeys: BackupKeys?
    var roomKeyCounts: RoomKeyCounts?
    
    var versionSpy: String?
    var backupKeySpy: MegolmV1BackupKey?
    var recoveryKeySpy: BackupRecoveryKey?
    var roomKeysSpy: [MXMegolmSessionData]?
    
    func enableBackup(key: MegolmV1BackupKey, version: String) throws {
        versionSpy = version
        backupKeySpy = key
    }
    
    func disableBackup() {
    }
    
    func saveRecoveryKey(key: BackupRecoveryKey, version: String?) throws {
        recoveryKeySpy = key
    }
    
    func verifyBackup(version: MXKeyBackupVersion) -> Bool {
        return true
    }
    
    var stubbedSignature = [String : [String : String]]()
    func sign(object: [AnyHashable : Any]) throws -> [String : [String : String]] {
        return stubbedSignature
    }
    
    func backupRoomKeys() async throws {
    }
    
    func importDecryptedKeys(roomKeys: [MXMegolmSessionData], progressListener: ProgressListener) throws -> KeysImportResult {
        roomKeysSpy = roomKeys
        return KeysImportResult(imported: Int64(roomKeys.count), total: Int64(roomKeys.count), keys: [:])
    }
    
    func exportRoomKeys(passphrase: String) throws -> Data {
        return Data()
    }
    
    func importRoomKeys(_ data: Data, passphrase: String, progressListener: ProgressListener) throws -> KeysImportResult {
        return KeysImportResult(imported: 0, total: 0, keys: [:])
    }
}

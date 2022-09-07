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

#if DEBUG && os(iOS)

import MatrixSDKCrypto

/// A set of protocols defining the functionality in `MatrixSDKCrypto` and separating them into logical units

/// Cryptographic identity of the currently signed-in user
@available(iOS 13.0.0, *)
protocol MXCryptoIdentity {
    var userId: String { get }
    var deviceId: String { get }
    var deviceCurve25519Key: String? { get }
    var deviceEd25519Key: String? { get }
}

/// Handler for cryptographic events in the sync loop
@available(iOS 13.0.0, *)
protocol MXCryptoSyncing: MXCryptoIdentity {
    func handleSyncResponse(
        toDevice: MXToDeviceSyncResponse?,
        deviceLists: MXDeviceListResponse?,
        deviceOneTimeKeysCounts: [String: NSNumber],
        unusedFallbackKeys: [String]?
    ) throws -> MXToDeviceSyncResponse
    
    func completeSync() async throws
}

/// Source of user devices and their cryptographic trust status
@available(iOS 13.0.0, *)
protocol MXCryptoDevicesSource: MXCryptoIdentity {
    func device(userId: String, deviceId: String) -> Device?
    func devices(userId: String) -> [Device]
}

/// Source of user identities and their cryptographic trust status
@available(iOS 13.0.0, *)
protocol MXCryptoUserIdentitySource: MXCryptoIdentity {
    func userIdentity(userId: String) -> UserIdentity?
    func isUserVerified(userId: String) -> Bool
    func downloadKeys(users: [String]) async throws
}

/// Event encryption and decryption
@available(iOS 13.0.0, *)
protocol MXCryptoEventEncrypting: MXCryptoIdentity {
    func shareRoomKeysIfNecessary(roomId: String, users: [String]) async throws
    func encrypt(_ content: [AnyHashable: Any], roomId: String, eventType: String, users: [String]) async throws -> [String: Any]
    func decryptEvent(_ event: MXEvent) throws -> MXEventDecryptionResult
}

/// Cross-signing functionality
@available(iOS 13.0.0, *)
protocol MXCryptoCrossSigning: MXCryptoUserIdentitySource {
    func crossSigningStatus() -> CrossSigningStatus
    func bootstrapCrossSigning(authParams: [AnyHashable: Any]) async throws
}

/// Lifecycle of verification request
@available(iOS 13.0.0, *)
protocol MXCryptoVerificationRequesting: MXCryptoIdentity {
    func requestSelfVerification(methods: [String]) async throws -> VerificationRequest
    func requestVerification(userId: String, roomId: String, methods: [String]) async throws -> VerificationRequest
    func verificationRequest(userId: String, flowId: String) -> VerificationRequest?
    func acceptVerificationRequest(userId: String, flowId: String, methods: [String]) async throws
    func cancelVerification(userId: String, flowId: String, cancelCode: String) async throws
}

/// Lifecycle of verification transaction
@available(iOS 13.0.0, *)
protocol MXCryptoVerifying: MXCryptoIdentity {
    func verification(userId: String, flowId: String) -> Verification?
    func confirmVerification(userId: String, flowId: String) async throws
    func cancelVerification(userId: String, flowId: String, cancelCode: String) async throws
}

/// Lifecycle of SAS-specific verification transaction
@available(iOS 13.0.0, *)
protocol MXCryptoSASVerifying: MXCryptoVerifying {
    func startSasVerification(userId: String, flowId: String) async throws -> Sas
    func acceptSasVerification(userId: String, flowId: String) async throws
    func emojiIndexes(sas: Sas) throws -> [Int]
}

#endif

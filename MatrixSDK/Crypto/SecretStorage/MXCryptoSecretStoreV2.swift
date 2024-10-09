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

enum MXCryptoError: Error {
    case secretDoesNotMatch
}

/// Secret store compatible with Rust-based Crypto V2, where
/// backup secrets are stored internally in the Crypto machine
/// and others have to be managed manually.
class MXCryptoSecretStoreV2: NSObject, MXCryptoSecretStore {

    private let backup: MXKeyBackup?
    private let backupEngine: MXKeyBackupEngine?
    private let crossSigning: MXCryptoCrossSigning
    private let log = MXNamedLog(name: "MXCryptoSecretStoreV2")
    
    init(backup: MXKeyBackup?, backupEngine: MXKeyBackupEngine?, crossSigning: MXCryptoCrossSigning) {
        self.backup = backup
        self.backupEngine = backupEngine
        self.crossSigning = crossSigning
    }
    
    func storeSecret(_ secret: String, withSecretId secretId: String, errorHandler: @escaping (Error) -> Void) {
        log.debug("Storing new secret \(secretId)")
        do {
            switch secretId as NSString {
            case MXSecretId.crossSigningMaster.takeUnretainedValue():
                try crossSigning.importCrossSigningKeys(
                    export: .init(
                        masterKey: secret,
                        selfSigningKey: nil,
                        userSigningKey: nil
                    )
                )
            case MXSecretId.crossSigningSelfSigning.takeUnretainedValue():
                try crossSigning.importCrossSigningKeys(
                    export: .init(
                        masterKey: nil,
                        selfSigningKey: secret,
                        userSigningKey: nil
                    )
                )
            case MXSecretId.crossSigningUserSigning.takeUnretainedValue():
                try crossSigning.importCrossSigningKeys(
                    export: .init(
                        masterKey: nil,
                        selfSigningKey: nil,
                        userSigningKey: secret
                    )
                )
            case MXSecretId.keyBackup.takeUnretainedValue():
                guard let version = backup?.keyBackupVersion?.version else {
                    log.error("No key backup version available")
                    return
                }
                
                let expectedPublicKey = try BackupRecoveryKey.fromBase64(key: secret).megolmV1PublicKey().publicKey
                
                guard let authData = backup?.keyBackupVersion?.authData,
                      MXCurve25519BackupAuthData(fromJSON: authData).publicKey == expectedPublicKey else {
                    errorHandler(MXCryptoError.secretDoesNotMatch)
                    return
                }
                
                let privateKey = MXBase64Tools.data(fromBase64: secret)
                backupEngine?.savePrivateKey(privateKey, version: version)
            default:
                log.error("Unsupported type of secret", context: secretId)
            }
        } catch {
            errorHandler(error)
        }
    }
    
    func hasSecret(withSecretId secretId: String) -> Bool {
        switch secretId as NSString {
        case MXSecretId.crossSigningMaster.takeUnretainedValue():
            return crossSigning.crossSigningStatus().hasMaster
        case MXSecretId.crossSigningSelfSigning.takeUnretainedValue():
            return crossSigning.crossSigningStatus().hasSelfSigning
        case MXSecretId.crossSigningUserSigning.takeUnretainedValue():
            return crossSigning.crossSigningStatus().hasUserSigning
        case MXSecretId.keyBackup.takeUnretainedValue():
            return backupEngine?.privateKey() != nil
        default:
            log.error("Unsupported type of secret", context: secretId)
            return false
        }
    }
    
    func secret(withSecretId secretId: String) -> String? {
        switch secretId as NSString {
        case MXSecretId.crossSigningMaster.takeUnretainedValue():
            return crossSigning.exportCrossSigningKeys()?.masterKey
        case MXSecretId.crossSigningSelfSigning.takeUnretainedValue():
            return crossSigning.exportCrossSigningKeys()?.selfSigningKey
        case MXSecretId.crossSigningUserSigning.takeUnretainedValue():
            return crossSigning.exportCrossSigningKeys()?.userSigningKey
        case MXSecretId.keyBackup.takeUnretainedValue():
            guard let privateKey = backupEngine?.privateKey() else {
                return nil
            }
            return MXBase64Tools.base64(from: privateKey)
        default:
            log.error("Unsupported type of secret", context: secretId)
            return nil
        }
    }
}

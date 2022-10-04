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

/// Secret store compatible with Rust-based Crypto V2, where
/// backup secrets are stored internally in the Crypto machine
/// and others have to be managed manually.
class MXCryptoSecretStoreV2: NSObject, MXCryptoSecretStore {
    
    private let backup: MXKeyBackup
    private let backupEngine: MXKeyBackupEngine
    private let log = MXNamedLog(name: "MXCryptoSecretStoreV2")
    
    init(backup: MXKeyBackup, backupEngine: MXKeyBackupEngine) {
        self.backup = backup
        self.backupEngine = backupEngine
    }
    
    func storeSecret(_ secret: String!, withSecretId secretId: String!) {
        guard let version = backup.keyBackupVersion?.version else {
            log.error("No key backup version available")
            return
        }

        if secretId == MXSecretId.keyBackup.takeUnretainedValue() as String {
            let privateKey = MXBase64Tools.data(fromBase64: secret)
            backupEngine.savePrivateKey(privateKey, version: version)
        } else {
            log.error("Not implemented")
        }
    }
    
    func secret(withSecretId secretId: String!) -> String! {
        if secretId == MXSecretId.keyBackup.takeUnretainedValue() as String {
            guard let privateKey = backupEngine.privateKey() else {
                return nil
            }
            return MXBase64Tools.base64(from: privateKey)
        } else {
            log.error("Not implemented")
            return nil
        }
    }
    
    func deleteSecret(withSecretId secretId: String!) {
        log.error("Not implemented")
    }
}

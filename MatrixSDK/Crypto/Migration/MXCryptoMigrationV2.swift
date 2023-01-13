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
    private let store: MXCryptoMigrationStore
    private let log = MXNamedLog(name: "MXCryptoMachineMigration")
    
    init(legacyStore: MXCryptoStore) {
        store = .init(legacyStore: legacyStore)
        super.init()
        OLMKit.sharedInstance().pickleKeyDelegate = self
    }
    
    func migrateCrypto() throws {
        log.debug("Starting migration")
        
        let data = try store.extractData(with: pickleKey())
        let url = try MXCryptoMachine.storeURL(for: data.account.userId)
        
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        
        let details = """
        Migration summary
          - user id         : \(data.account.userId)
          - device id       : \(data.account.deviceId)
          - olm_sessions    : \(data.sessions.count)
          - megolm_sessions : \(data.inboundGroupSessions.count)
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
        
        log.debug("Migration complete")
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
        log.debug("Migration progress \(progress) out of \(total)")
    }
}

#endif

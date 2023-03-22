// 
// Copyright 2023 The Matrix.org Foundation C.I.C
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

/// Redirects logs originating in `MatrixSDKCrypto` into `MXLog`
class MXCryptoSDKLogger: Logger {
    static let shared = MXCryptoSDKLogger()
    
    init() {
        setLogger(logger: self)
    }
    
    func log(logLine: String) {
        // Excluding some auto-generated logs that are not useful
        // This will be changed in rust-sdk directly
        let ignored = [
            "::uniffi_api:",
            "::backup_recovery_key: decrypt_v1",
            "matrix_sdk_crypto_ffi::machine: backup_enabled",
            "matrix_sdk_crypto_ffi::machine: room_key_counts",
            "matrix_sdk_crypto_ffi::machine: user_id",
            "matrix_sdk_crypto_ffi::machine: identity_keys"
        ]
        
        for ignore in ignored {
            if logLine.contains(ignore) {
                return
            }
        }
        
        MXLog.debug("[MXCryptoSDK] \(logLine)")
    }
}

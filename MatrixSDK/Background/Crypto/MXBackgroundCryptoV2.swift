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

/// An implementation of `MXBackgroundCrypto` which uses [matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk/tree/main/crates/matrix-sdk-crypto)
/// under the hood.
class MXBackgroundCryptoV2: MXBackgroundCrypto {
    enum Error: Swift.Error {
        case missingCredentials
    }
    
    private let machine: MXCryptoMachine
    private let log = MXNamedLog(name: "MXBackgroundCryptoV2")
    
    init(credentials: MXCredentials, restClient: MXRestClient) throws {
        guard
            let userId = credentials.userId,
            let deviceId = credentials.deviceId
        else {
            throw Error.missingCredentials
        }
        
        // `MXCryptoMachine` will load the same store as the main application meaning that background and foreground
        // sync services have access to the same data / keys. Possible race conditions are handled internally.
        machine = try MXCryptoMachine(
            userId: userId,
            deviceId: deviceId,
            restClient: restClient,
            getRoomAction: { [log] _ in
                log.error("The background crypto should not be accessing rooms")
                return nil
            }
        )
    }
    
    func handleSyncResponse(_ syncResponse: MXSyncResponse) {
        let toDeviceCount = syncResponse.toDevice?.events.count ?? 0
        
        log.debug("Handling new sync response with \(toDeviceCount) to-device event(s)")
        
        do {
            _ = try machine.handleSyncResponse(
                toDevice: syncResponse.toDevice,
                deviceLists: syncResponse.deviceLists,
                deviceOneTimeKeysCounts: syncResponse.deviceOneTimeKeysCount ?? [:],
                unusedFallbackKeys: syncResponse.unusedFallbackKeys
            )
        } catch {
            log.error("Failed handling sync response", context: error)
        }
    }
    
    func canDecryptEvent(_ event: MXEvent) -> Bool {
        if !event.isEncrypted {
            return true
        }
        
        guard
            let _ = event.content["sender_key"] as? String,
            let _ = event.content["session_id"] as? String
        else {
            return false
        }
        
        do {
            // Rust-sdk does not expose api to see if we have a given session key yet (will be added in the future)
            // so for the time being to find out if we can decrypt we simply perform the (more expensive) decryption
            _ = try machine.decryptRoomEvent(event)
            return true
        } catch {
            return false
        }
    }
    
    func decryptEvent(_ event: MXEvent) throws {
        let decrypted = try machine.decryptRoomEvent(event)
        let result = try MXEventDecryptionResult(event: decrypted)
        event.setClearData(result)
    }
}

#endif

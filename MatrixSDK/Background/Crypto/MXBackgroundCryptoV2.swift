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

/// An implementation of `MXBackgroundCrypto` which uses [matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk/tree/main/crates/matrix-sdk-crypto)
/// under the hood.
class MXBackgroundCryptoV2: MXBackgroundCrypto {
    enum Error: Swift.Error {
        case missingCredentials
    }
    
    private let credentials: MXCredentials
    private let restClient: MXRestClient
    private let log = MXNamedLog(name: "MXBackgroundCryptoV2")
    
    init(credentials: MXCredentials, restClient: MXRestClient) {
        self.credentials = credentials
        self.restClient = restClient
        log.debug("Initialized background crypto module")
    }
    
    func handleSyncResponse(_ syncResponse: MXSyncResponse) async {
        let syncId = UUID().uuidString
        let details = """
        Handling new sync response `\(syncId)`
          - to-device events : \(syncResponse.toDevice?.events.count ?? 0)
          - devices changed  : \(syncResponse.deviceLists?.changed?.count ?? 0)
          - devices left     : \(syncResponse.deviceLists?.left?.count ?? 0)
          - one time keys    : \(syncResponse.deviceOneTimeKeysCount?[kMXKeySignedCurve25519Type] ?? 0)
          - fallback keys    : \(syncResponse.unusedFallbackKeys ?? [])
        """
        log.debug(details)
        
        do {
            let machine = try createMachine()
            _ = try await machine.handleSyncResponse(
                toDevice: syncResponse.toDevice,
                deviceLists: syncResponse.deviceLists,
                deviceOneTimeKeysCounts: syncResponse.deviceOneTimeKeysCount ?? [:],
                unusedFallbackKeys: syncResponse.unusedFallbackKeys,
                nextBatchToken: syncResponse.nextBatch
            )
        } catch {
            log.error("Failed handling sync response", context: error)
        }
        
        log.debug("Completed handling sync response `\(syncId)`")
    }
    
    func canDecryptEvent(_ event: MXEvent) -> Bool {
        let eventId = event.eventId ?? ""
        
        if !event.isEncrypted {
            log.debug("Event \(eventId) is not encrypted")
            return true
        }
        
        guard
            let _ = event.content["sender_key"] as? String,
            let sessionId = event.content["session_id"] as? String
        else {
            log.error("Event does not contain session_id", context: [
                "event_id": eventId
            ])
            return false
        }
        
        do {
            // Rust-sdk does not expose api to see if we have a given session key yet (will be added in the future)
            // so for the time being to find out if we can decrypt we simply perform the (more expensive) decryption
            let machine = try createMachine()
            _ = try machine.decryptRoomEvent(event)
            log.debug("Event `\(eventId)` can be decrypted with session `\(sessionId)`")
            return true
        } catch DecryptionError.MissingRoomKey {
            log.warning("We do not have keys to decrypt event `\(eventId)` with session `\(sessionId)`")
            return false
        } catch {
            log.warning("We cannot decrypt event `\(eventId)` with session `\(sessionId)`")
            return false
        }
    }
    
    func decryptEvent(_ event: MXEvent) throws {
        let eventId = event.eventId ?? ""
        log.debug("Decrypting event `\(eventId)`")
        
        do {
            let machine = try createMachine()
            let decrypted = try machine.decryptRoomEvent(event)
            let result = try MXEventDecryptionResult(event: decrypted)
            event.setClearData(result)
            
            log.debug("Successfully decrypted event `\(result.clearEvent["type"] ?? "unknown")` eventId `\(eventId)`")
        } catch {
            log.error("Failed to decrypt event", context: error)
            throw error
        }
    }
    
    // `MXCryptoMachine` will load the same store as the main application meaning that background and foreground
    // sync services have access to the same data / keys. The machine is not fully multi-thread and multi-process
    // safe, and until this is resolved we open a new instance of `MXCryptoMachine` on each background operation
    // to ensure we are always up-to-date with whatever has been written by the foreground process in the meanwhile.
    // See https://github.com/matrix-org/matrix-rust-sdk/issues/1415 for more details.
    private func createMachine() throws -> MXCryptoMachine {
        guard
            let userId = credentials.userId,
            let deviceId = credentials.deviceId
        else {
            throw Error.missingCredentials
        }
         
        return try MXCryptoMachine(
            userId: userId,
            deviceId: deviceId,
            restClient: restClient,
            getRoomAction: { [log] _ in
                log.error("The background crypto should not be accessing rooms")
                return nil
            }
        )
    }
}

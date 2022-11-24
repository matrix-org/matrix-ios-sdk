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

#if DEBUG

import OLMKit
import MatrixSDKCrypto

struct MXCryptoMigrationStore {
    enum Error: Swift.Error {
        case missingAccount
    }
    
    let legacyStore: MXCryptoStore
    
    func extractData(with pickleKey: Data) throws -> MigrationData {
        return .init(
            account: try pickledAccount(pickleKey: pickleKey),
            sessions: olmSessions(pickleKey: pickleKey),
            inboundGroupSessions: megolmSessions(pickleKey: pickleKey),
            backupVersion: legacyStore.backupVersion,
            backupRecoveryKey: backupRecoveryKey(),
            pickleKey: [UInt8](pickleKey),
            crossSigning: crossSigning(),
            trackedUsers: trackedUsers()
        )
    }
    
    private func pickledAccount(pickleKey: Data) throws -> PickledAccount {
        guard
            let userId = legacyStore.userId(),
            let deviceId = legacyStore.deviceId(),
            let account = legacyStore.account()
        else {
            throw Error.missingAccount
        }
        return try PickledAccount(
            userId: userId,
            deviceId: deviceId,
            account: account,
            pickleKey: pickleKey
        )
    }
    
    private func olmSessions(pickleKey: Data) -> [PickledSession] {
        return legacyStore
            .sessions()?
            .compactMap {
                do {
                    return try PickledSession(session: $0, pickleKey: pickleKey)
                } catch {
                    MXLog.error("[MXCryptoMigrationStore] cannot extract olm session", context: error)
                    return nil
                }
            } ?? []
    }
    
    private func megolmSessions(pickleKey: Data) -> [PickledInboundGroupSession] {
        guard let sessions = legacyStore.inboundGroupSessions() else {
            return []
        }
        
        let sessionsToBackup = Set(
            legacyStore.inboundGroupSessions(toBackup: UInt.max)
                .compactMap { $0.session?.sessionIdentifier() }
        )
        
        return sessions.compactMap {
            do {
                return try PickledInboundGroupSession(
                    session: $0,
                    pickleKey: pickleKey,
                    backedUp: !sessionsToBackup.contains($0.session?.sessionIdentifier() ?? "")
                )
            } catch {
                MXLog.error("[MXCryptoMigrationStore] cannot extract megolm session", context: error)
                return nil
            }
        }
    }
    
    private func backupRecoveryKey() -> String? {
        guard let privateKey = secret(for: MXSecretId.keyBackup) else {
            return nil
        }
        
        let data = MXBase64Tools.data(fromBase64: privateKey)
        return MXRecoveryKey.encode(data)
    }
    
    private func crossSigning() -> CrossSigningKeyExport {
        let master = secret(for: MXSecretId.crossSigningMaster)
        let selfSigning = secret(for: MXSecretId.crossSigningSelfSigning)
        let userSigning = secret(for: MXSecretId.crossSigningUserSigning)
        
        return .init(
            masterKey: master,
            selfSigningKey: selfSigning,
            userSigningKey: userSigning
        )
    }
    
    private func trackedUsers() -> [String] {
        var users = [String]()
        for (user, status) in legacyStore.deviceTrackingStatus() ?? [:] {
            if status != 0 {
                users.append(user)
            }
        }
        return users
    }
    
    private func secret(for secretId: Unmanaged<NSString>) -> String? {
        return legacyStore.secret(withSecretId: secretId.takeUnretainedValue() as String)
    }
}

private extension PickledAccount {
    init(
        userId: String,
        deviceId: String,
        account: OLMAccount,
        pickleKey: Data
    ) throws {
        let pickle = try account.serializeData(withKey: pickleKey)
        self.init(
            userId: userId,
            deviceId: deviceId,
            pickle: pickle,
            shared: true, // Not yet implemented
            uploadedSignedKeyCount: 50 // Not yet implemented
        )
    }
}

private extension PickledSession {
    init(session: MXOlmSession, pickleKey: Data) throws {
        let pickle = try session.session.serializeData(withKey: pickleKey)
        let time = "\(Int(session.lastReceivedMessageTs))"
        
        self.init(
            pickle: pickle,
            senderKey: session.deviceKey,
            createdUsingFallbackKey: false, // Not yet implemented
            creationTime: time, // Not yet implemented
            lastUseTime: time
        )
    }
}

private extension PickledInboundGroupSession {
    enum Error: Swift.Error {
        case invalidSession
    }
    
    init(session: MXOlmInboundGroupSession, pickleKey: Data, backedUp: Bool) throws {
        guard
            let senderKey = session.senderKey,
            let roomId = session.roomId
        else {
            throw Error.invalidSession
        }
        
        let pickle = try session.session.serializeData(withKey: pickleKey)
        
        self.init(
            pickle: pickle,
            senderKey: senderKey,
            signingKey: session.keysClaimed ?? [:],
            roomId: roomId,
            forwardingChains: session.forwardingCurve25519KeyChain ?? [],
            imported: session.isUntrusted,
            backedUp: backedUp
        )
    }
}

#endif

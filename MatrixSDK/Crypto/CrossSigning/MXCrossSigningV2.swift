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

/// A work-in-progress implementation of `MXCrossSigning` instantiated and used by `MXCryptoV2`.
class MXCrossSigningV2: NSObject, MXCrossSigning {
    enum Error: Swift.Error {
        case missingAuthSession
    }
    
    var state: MXCrossSigningState {
        if hasAllPrivateKeys {
            return .canCrossSign
        } else if let info = myUserCrossSigningKeys {
            if info.trustLevel.isVerified {
                return .trustCrossSigning
            } else {
                return .crossSigningExists
            }
        } else {
            return .notBootstrapped
        }
    }
    
    private(set) var myUserCrossSigningKeys: MXCrossSigningInfo?
    
    var canTrustCrossSigning: Bool {
        return state.rawValue >= MXCrossSigningState.trustCrossSigning.rawValue
    }
    
    var canCrossSign: Bool {
        return state.rawValue >= MXCrossSigningState.canCrossSign.rawValue
    }
    
    var hasAllPrivateKeys: Bool {
        let status = crossSigning.crossSigningStatus()
        return status.hasMaster && status.hasSelfSigning && status.hasUserSigning
    }
    
    private let crossSigning: MXCryptoCrossSigning
    private let infoSource: MXCrossSigningInfoSource
    private let restClient: MXRestClient
    
    private let log = MXNamedLog(name: "MXCrossSigningV2")
    
    init(crossSigning: MXCryptoCrossSigning, restClient: MXRestClient) {
        self.crossSigning = crossSigning
        self.infoSource = MXCrossSigningInfoSource(source: crossSigning)
        self.restClient = restClient
    }
    
    func setup(
        withPassword password: String,
        success: @escaping () -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        Task {
            do {
                let authParams = try await authParameters(password: password)
                try await crossSigning.bootstrapCrossSigning(authParams: authParams)
                await MainActor.run {
                    success()
                }
            } catch {
                log.error("Cannot setup cross signing", context: error)
                await MainActor.run {
                    failure(error)
                }
            }
        }
    }
    
    func setup(
        withAuthParams authParams: [AnyHashable: Any],
        success: @escaping () -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        Task {
            do {
                try await crossSigning.bootstrapCrossSigning(authParams: authParams)
                await MainActor.run {
                    success()
                }
            } catch {
                log.error("Cannot setup cross signing", context: error)
                await MainActor.run {
                    failure(error)
                }
            }
        }
    }
    
    func refreshState(
        success: ((Bool) -> Void)?,
        failure: ((Swift.Error) -> Void)? = nil
    ) {
        Task {
            do {
                try await crossSigning.downloadKeys(users: [crossSigning.userId])
                myUserCrossSigningKeys = infoSource.crossSigningInfo(userId: crossSigning.userId)
                
                await MainActor.run {
                    success?(true)
                }
            } catch {
                log.error("Cannot refresh cross signing state", context: error)
                await MainActor.run {
                    failure?(error)
                }
            }
        }
    }

    func crossSignDevice(
        withDeviceId deviceId: String,
        success: @escaping () -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.error("Not implemented")
        success()
    }

    func signUser(
        withUserId userId: String,
        success: @escaping () -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.error("Not implemented")
        success()
    }

    func requestPrivateKeys(
        toDeviceIds deviceIds: [String]?,
        success: @escaping () -> Void,
        onPrivateKeysReceived: @escaping () -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.error("Not implemented")
        success()
    }
    
    func isSecretValid(_ secret: String, forPublicKeys keys: String) -> Bool {
        log.error("Not implemented")
        return false
    }
    
    // MARK: - Private
    
    private func authParameters(password: String) async throws -> [AnyHashable: Any] {
        let authSession: MXAuthenticationSession? = try await performCallbackRequest { completion in
            restClient.authSession {
                completion(.success($0))
            } failure: {
                completion(.failure($0 ?? Error.missingAuthSession))
            }
        }

        guard
            let authSession = authSession,
            let session = authSession.session,
            let userId = restClient.credentials?.userId
        else {
            log.error("Missing parameters")
            throw Error.missingAuthSession
        }

        return [
            "session": session,
            "user": userId,
            "password": password,
            "type": kMXLoginFlowTypePassword
        ]
    }
}

#endif

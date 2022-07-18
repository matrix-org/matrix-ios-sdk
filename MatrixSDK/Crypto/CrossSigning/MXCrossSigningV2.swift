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

/// A work-in-progress subclass of `MXCrossSigning` instantiated and used by `MXCryptoV2`.
///
/// Note: `MXCrossSigning` will be defined as a protocol in the future to avoid subclasses.
@available(iOS 13.0.0, *)
class MXCrossSigningV2: MXCrossSigning {
    enum Error: Swift.Error {
        case missingAuthSession
    }
    
    override var crypto: MXCrypto? {
        assertionFailure("Crypto module should not be accessed directly")
        return nil
    }
    
    override var state: MXCrossSigningState {
        log.debug("Only partial implementation")
        return hasAllPrivateKeys ? .canCrossSign : .notBootstrapped
    }
    
    override var canTrustCrossSigning: Bool {
        return state.rawValue >= MXCrossSigningState.trustCrossSigning.rawValue
    }
    
    override var canCrossSign: Bool {
        return state.rawValue >= MXCrossSigningState.canCrossSign.rawValue
    }
    
    override var hasAllPrivateKeys: Bool {
        let status = machine.crossSigningStatus()
        return status.hasMaster && status.hasSelfSigning && status.hasUserSigning
    }
    
    private let machine: MXCryptoMachine
    private let restClient: MXRestClient
    private let log = MXNamedLog(name: "MXCrossSigningV2")
    
    init(machine: MXCryptoMachine, restClient: MXRestClient) {
        self.machine = machine
        self.restClient = restClient
    }
    
    override func setup(
        withPassword password: String,
        success: @escaping () -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        Task {
            do {
                let authParams = try await authParameters(password: password)
                try await machine.bootstrapCrossSigning(authParams: authParams)
                await MainActor.run {
                    success()
                }
            } catch {
                log.error("Cannot setup cross signing", error: error)
                await MainActor.run {
                    failure(error)
                }
            }
        }
    }
    
    override func setup(
        withAuthParams authParams: [AnyHashable: Any],
        success: @escaping () -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        Task {
            do {
                try await machine.bootstrapCrossSigning(authParams: authParams)
                await MainActor.run {
                    success()
                }
            } catch {
                log.error("Cannot setup cross signing", error: error)
                await MainActor.run {
                    failure(error)
                }
            }
        }
    }
    
    override func refreshState(
        success: ((Bool) -> Void)?,
        failure: ((Swift.Error) -> Void)? = nil
    ) {
        log.debug("Not implemented")
        success?(true)
    }

    override func crossSignDevice(
        withDeviceId deviceId: String,
        success: @escaping () -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.debug("Not implemented")
        success()
    }

    override func signUser(
        withUserId userId: String,
        success: @escaping () -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.debug("Not implemented")
        success()
    }

    override func requestPrivateKeys(
        toDeviceIds deviceIds: [String]?,
        success: @escaping () -> Void,
        onPrivateKeysReceived: @escaping () -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.debug("Not implemented")
        success()
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

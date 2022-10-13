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

/// Verification request originating from `MatrixSDKCrypto`
class MXKeyVerificationRequestV2: NSObject, MXKeyVerificationRequest {
    var state: MXKeyVerificationRequestState {
        // State as enum will be moved to MatrixSDKCrypto in the future
        // to avoid the mapping of booleans into state
        if request.isDone {
            return MXKeyVerificationRequestStateAccepted
        } else if request.isCancelled {
            return MXKeyVerificationRequestStateCancelled
        } else if request.isReady {
            return MXKeyVerificationRequestStateReady
        } else if request.isPassive {
            return MXKeyVerificationRequestStatePending
        }
        return MXKeyVerificationRequestStatePending
    }
    
    var reasonCancelCode: MXTransactionCancelCode? {
        guard let info = request.cancelInfo else {
            return nil
        }
        return .init(
            value: info.cancelCode,
            humanReadable: info.reason
        )
    }
    
    var myUserId: String {
        return handler.userId
    }
    
    var isFromMyUser: Bool {
        return otherUser == myUserId
    }
    
    var isFromMyDevice: Bool {
        return request.weStarted
    }
    
    var requestId: String {
        return request.flowId
    }
    
    let transport: MXKeyVerificationTransport
    
    var roomId: String? {
        return request.roomId
    }
    
    var otherUser: String {
        return request.otherUserId
    }
    
    var otherDevice: String? {
        return request.otherDeviceId
    }
    
    var methods: [String] {
        return (isFromMyDevice ? myMethods : otherMethods) ?? []
    }
    
    var myMethods: [String]? {
        return request.ourMethods
    }
    
    var otherMethods: [String]? {
        return request.theirMethods
    }
    
    private var request: VerificationRequest
    private let handler: MXCryptoVerificationRequesting
    
    private let log = MXNamedLog(name: "MXKeyVerificationRequestV2")
    
    init(request: VerificationRequest, transport: MXKeyVerificationTransport, handler: MXCryptoVerificationRequesting) {
        log.debug("Creating new request")
        
        self.request = request
        self.transport = transport
        self.handler = handler
    }
    
    func processUpdates() -> MXKeyVerificationUpdateResult {
        guard let request = handler.verificationRequest(userId: otherUser, flowId: requestId) else {
            log.debug("Request was removed")
            return .removed
        }
        
        guard self.request != request else {
            return .noUpdates
        }
        
        log.debug("Request was updated \(request)")
        self.request = request
        return .updated
    }
    
    func accept(
        withMethods methods: [String],
        success: @escaping () -> Void,
        failure: @escaping (Error) -> Void
    ) {
        Task {
            do {
                try await handler.acceptVerificationRequest(
                    userId: otherUser,
                    flowId: requestId,
                    methods: methods
                )
                await MainActor.run {
                    log.debug("Accepted request")
                    success()
                }
            } catch {
                await MainActor.run {
                    log.error("Failed accepting request", context: error)
                    failure(error)
                }
            }
        }
    }
    
    func cancel(
        with code: MXTransactionCancelCode,
        success: (() -> Void)?,
        failure: ((Error) -> Void)? = nil
    ) {
        Task {
            do {
                try await handler.cancelVerification(
                    userId: otherUser,
                    flowId: requestId,
                    cancelCode: code.value
                )
                await MainActor.run {
                    log.debug("Cancelled request")
                    success?()
                }
            } catch {
                await MainActor.run {
                    log.error("Failed cancelling request", context: error)
                    failure?(error)
                }
            }
        }
    }
}

#endif

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

import MatrixSDKCrypto

/// Verification request originating from `MatrixSDKCrypto`
class MXKeyVerificationRequestV2: NSObject, MXKeyVerificationRequest {
    typealias CancelAction = (MXKeyVerificationRequest, MXTransactionCancelCode) -> Void
    
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
    
    var isFromMyUser: Bool {
        return request.weStarted
    }
    
    var isFromMyDevice: Bool {
        // Not exposed on the underlying request,
        // assuming that if request is from us, it is from our devide
        log.debug("Not fully implemented")
        return isFromMyUser
    }
    
    var requestId: String {
        return request.flowId
    }
    
    var transport: MXKeyVerificationTransport {
        log.debug("Not fully implemented")
        return .directMessage
    }
    
    var otherUser: String {
        return request.otherUserId
    }
    
    var otherDevice: String? {
        return request.otherDeviceId
    }
    
    var methods: [String] {
        return (isFromMyUser ? myMethods : otherMethods) ?? []
    }
    
    var myMethods: [String]? {
        return request.ourMethods
    }
    
    var otherMethods: [String]? {
        return request.theirMethods
    }
    
    private var request: VerificationRequest
    private let cancelAction: CancelAction
    
    private let log = MXNamedLog(name: "MXKeyVerificationRequestV2")
    
    init(request: VerificationRequest, cancelAction: @escaping CancelAction) {
        self.request = request
        self.cancelAction = cancelAction
    }
    
    func update(request: VerificationRequest) {
        guard self.request != request else {
            return
        }
        self.request = request
        NotificationCenter.default.post(name: .MXKeyVerificationRequestDidChange, object: self)
    }
    
    func accept(
        withMethods methods: [String],
        success: @escaping () -> Void,
        failure: @escaping (Error) -> Void
    ) {
        log.debug("Not implemented")
    }
    
    func cancel(
        with code: MXTransactionCancelCode,
        success: (() -> Void)?,
        failure: ((Error) -> Void)? = nil
    ) {
        cancelAction(self, code)
        success?()
    }
}

#endif

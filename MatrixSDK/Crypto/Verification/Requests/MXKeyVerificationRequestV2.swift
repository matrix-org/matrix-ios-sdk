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
    enum Error: Swift.Error {
        case cannotAccept
        case cannotCancel
        case cannotStartSasVerification
        case cannotStartQrVerification
    }
    
    private(set) var state: MXKeyVerificationRequestState = MXKeyVerificationRequestStatePending
    
    var reasonCancelCode: MXTransactionCancelCode? {
        guard let info = request.cancelInfo() else {
            return nil
        }
        return .init(
            value: info.cancelCode,
            humanReadable: info.reason
        )
    }
    
    var myUserId: String {
        handler.userId
    }
    
    var isFromMyUser: Bool {
        otherUser == myUserId
    }
    
    var isFromMyDevice: Bool {
        request.weStarted()
    }
    
    var requestId: String {
        request.flowId()
    }
    
    var transport: MXKeyVerificationTransport {
        roomId != nil ? .directMessage : .toDevice
    }
    
    var roomId: String? {
        request.roomId()
    }
    
    var otherUser: String {
        request.otherUserId()
    }
    
    var otherDevice: String? {
        request.otherDeviceId()
    }
    
    var methods: [String] {
        (isFromMyDevice ? myMethods : otherMethods) ?? []
    }
    
    var myMethods: [String]? {
        request.ourSupportedMethods()
    }
    
    var otherMethods: [String]? {
        request.theirSupportedMethods()
    }
    
    private let request: VerificationRequestProtocol
    private let handler: MXCryptoVerifying
    
    private let log = MXNamedLog(name: "MXKeyVerificationRequestV2")
    
    init(request: VerificationRequestProtocol, handler: MXCryptoVerifying) {
        self.request = request
        self.handler = handler
        self.state = request.state
    }
    
    // Updates to state will be handled in rust-sdk in a fuiture PR
    func processUpdates() -> MXKeyVerificationUpdateResult {
        guard state != request.state else {
            return .noUpdates
        }
        
        log.debug("Request was updated - \(request)")
        state = request.state
        return .updated
    }
    
    func accept(
        withMethods methods: [String],
        success: @escaping () -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.debug("->")
        guard let outgoingRequest = request.accept(methods: methods) else {
            log.error("Cannot accept request")
            failure(Error.cannotAccept)
            return
        }
        
        Task {
            do {
                try await handler.handleOutgoingVerificationRequest(outgoingRequest)
                log.debug("Accepted request")
                await MainActor.run {
                    success()
                }
            } catch {
                log.error("Failed accepting request", context: error)
                await MainActor.run {
                    failure(error)
                }
            }
        }
    }
    
    func cancel(
        with code: MXTransactionCancelCode,
        success: (() -> Void)?,
        failure: ((Swift.Error) -> Void)? = nil
    ) {
        log.debug("->")
        guard let outgoingRequest = request.cancel() else {
            log.error("Cannot cancel request")
            failure?(Error.cannotCancel)
            return
        }
        
        Task {
            do {
                try await handler.handleOutgoingVerificationRequest(outgoingRequest)
                log.debug("Cancelled request")
                await MainActor.run {
                    success?()
                }
            } catch {
                log.error("Failed cancelling request", context: error)
                await MainActor.run {
                    failure?(error)
                }
            }
        }
    }
    
    func startSasVerification() async throws -> SasProtocol {
        guard let result = try request.startSasVerification() else {
            log.failure("Cannot start Sas")
            throw Error.cannotStartSasVerification
        }
        
        try await handler.handleOutgoingVerificationRequest(result.request)
        return result.sas
    }
    
    func startQrVerification() throws -> QrCodeProtocol {
        guard let qrCode = try request.startQrVerification() else {
            log.failure("Cannot start QrCode")
            throw Error.cannotStartQrVerification
        }
        return qrCode
    }
}

extension VerificationRequestProtocol {
    var state: MXKeyVerificationRequestState {
        // State as enum will be moved to MatrixSDKCrypto in the future
        // to avoid the mapping of booleans into state
        if isDone() {
            return MXKeyVerificationRequestStateAccepted
        } else if isCancelled() {
            return MXKeyVerificationRequestStateCancelled
        } else if isReady() {
            return MXKeyVerificationRequestStateReady
        } else if isPassive() {
            return MXKeyVerificationRequestStatePending
        }
        return MXKeyVerificationRequestStatePending
    }
}

#endif

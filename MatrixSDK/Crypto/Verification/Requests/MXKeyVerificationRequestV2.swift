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

/// Verification request originating from `MatrixSDKCrypto`
class MXKeyVerificationRequestV2: NSObject, MXKeyVerificationRequest { 
    enum Error: Swift.Error {
        case cannotAccept
        case cannotCancel
        case cannotStartSasVerification
        case cannotStartQrVerification
    }
    
    private(set) var state: MXKeyVerificationRequestState = MXKeyVerificationRequestStatePending {
        didSet {
            guard state != oldValue else {
                return
            }
            
            log.debug("\(oldValue.description) -> \(state.description)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .MXKeyVerificationRequestDidChange, object: self)
            }
        }
    }
    
    let requestId: String
    let transport: MXKeyVerificationTransport
    
    let myUserId: String
    let otherUser: String
    let otherDevice: String?
    
    let isFromMyUser: Bool
    let isFromMyDevice: Bool
    
    let roomId: String?
    
    var methods: [String] {
        (isFromMyDevice ? myMethods : otherMethods) ?? []
    }
    private (set) var myMethods: [String]?
    private (set) var otherMethods: [String]?
    
    private (set) var reasonCancelCode: MXTransactionCancelCode?

    private let request: VerificationRequestProtocol
    private let handler: MXCryptoVerifying
    private let log = MXNamedLog(name: "MXKeyVerificationRequestV2")
    
    init(request: VerificationRequestProtocol, handler: MXCryptoVerifying) {
        self.request = request
        self.handler = handler
        
        self.requestId = request.flowId()
        self.transport = request.roomId() != nil ?.directMessage : .toDevice
        
        self.myUserId = handler.userId
        self.otherUser = request.otherUserId()
        self.otherDevice = request.otherDeviceId()
        self.isFromMyUser = otherUser == myUserId
        self.isFromMyDevice = request.weStarted()
        self.roomId = request.roomId()
        self.myMethods = request.ourSupportedMethods()
        self.otherMethods = request.theirSupportedMethods()
        
        super.init()
        
        request.setChangesListener(listener: self)
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
            log.error("Cannot start QrCode")
            throw Error.cannotStartQrVerification
        }
        return qrCode
    }
}

extension MXKeyVerificationRequestV2: VerificationRequestListener {
    func onChange(state: VerificationRequestState) {
        log.debug("\(state)")
        
        switch state {
        case .requested:
            self.state = MXKeyVerificationRequestStatePending
        case .ready(let theirMethods, let ourMethods):
            self.myMethods = ourMethods
            self.otherMethods = theirMethods
            self.state = MXKeyVerificationRequestStateReady
        case .done:
            self.state = MXKeyVerificationRequestStateAccepted
        case .cancelled(let cancelInfo):
            reasonCancelCode = MXTransactionCancelCode(
                value: cancelInfo.cancelCode,
                humanReadable: cancelInfo.reason
            )
            self.state = cancelInfo.cancelledByUs ? MXKeyVerificationRequestStateCancelledByMe : MXKeyVerificationRequestStateCancelled
        }
    }
}

private extension MXKeyVerificationRequestState {
    var description: String {
        switch self {
        case MXKeyVerificationRequestStatePending:
            return "pending"
        case MXKeyVerificationRequestStateExpired:
            return "expired"
        case MXKeyVerificationRequestStateCancelled:
            return "cancelled"
        case MXKeyVerificationRequestStateCancelledByMe:
            return "cancelledByMe"
        case MXKeyVerificationRequestStateReady:
            return "ready"
        case MXKeyVerificationRequestStateAccepted:
            return "accepted"
        default:
            return "unknown"
        }
    }
}


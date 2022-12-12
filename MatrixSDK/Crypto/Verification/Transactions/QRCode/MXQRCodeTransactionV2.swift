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

/// QR transaction originating from `MatrixSDKCrypto`
class MXQRCodeTransactionV2: NSObject, MXQRCodeTransaction {
    enum Error: Swift.Error {
        case cannotCancel
    }
    
    var state: MXQRCodeTransactionState {
        qrCode.state
    }

    var qrCodeData: MXQRCodeData? {
        guard let code = qrCode.generateQrCode() else {
            log.error("Cannot generate QR code")
            return nil
        }
        let data = MXBase64Tools.data(fromBase64: code)
        return MXQRCodeDataCoder().decode(data)
    }

    var transactionId: String {
        qrCode.flowId()
    }

    var transport: MXKeyVerificationTransport {
        dmRoomId != nil ? .directMessage : .toDevice
    }

    let isIncoming: Bool

    var otherUserId: String {
        qrCode.otherUserId()
    }

    var otherDeviceId: String {
        qrCode.otherDeviceId()
    }

    var reasonCancelCode: MXTransactionCancelCode? {
        guard let info = qrCode.cancelInfo() else {
            return nil
        }
        return .init(
            value: info.cancelCode,
            humanReadable: info.reason
        )
    }

    var error: Swift.Error? {
        nil
    }

    var dmRoomId: String? {
        qrCode.roomId()
    }

    var dmEventId: String? {
        dmRoomId != nil ? transactionId : nil
    }

    private var qrCode: QrCodeProtocol
    private let handler: MXCryptoVerifying
    private let log = MXNamedLog(name: "MXQRCodeTransactionV2")

    init(qrCode: QrCodeProtocol, isIncoming: Bool, handler: MXCryptoVerifying) {
        self.qrCode = qrCode
        self.handler = handler
        
        self.isIncoming = isIncoming
    }
    
    // Updates to state will be handled in rust-sdk in a fuiture PR
    func processUpdates() -> MXKeyVerificationUpdateResult {
        guard
            let verification = handler.verification(userId: otherUserId, flowId: transactionId),
            case .qrCode(let qrCode) = verification
        else {
            log.debug("Transaction was removed")
            return .removed
        }

        guard self.qrCode.state != qrCode.state else {
            return .noUpdates
        }

        log.debug("Transaction was updated - \(qrCode)")
        self.qrCode = qrCode
        return .updated
    }

    func userHasScannedOtherQrCodeData(_ otherQRCodeData: MXQRCodeData) {
        log.debug("->")
        
        guard let request = handler.verificationRequest(userId: otherUserId, flowId: transactionId) else {
            log.failure("There is no corresponding verification request")
            return
        }
        
        let data = MXQRCodeDataCoder().encode(otherQRCodeData)
        let string = MXBase64Tools.base64(from: data)
        guard let result = request.scanQrCode(data: string) else {
            log.failure("Failed scanning QR code")
            return
        }
        
        Task {
            do {
                try await handler.handleOutgoingVerificationRequest(result.request)
                log.debug("Scanned QR code")
                await MainActor.run {
                    self.qrCode = result.qr
                }
            } catch {
                log.error("Failed scanning QR code", context: error)
            }
        }
    }

    func otherUserScannedMyQrCode(_ otherUserScanned: Bool) {
        guard otherUserScanned else {
            log.debug("Cancelling due to mismatched keys")
            cancel(with: .mismatchedKeys())
            return
        }
        
        guard let result = qrCode.confirm() else {
            log.failure("Failed confirming QR code")
            return
        }

        log.debug("Confirming verification")
        Task {
            do {
                try await handler.handleVerificationConfirmation(result)
                log.debug("Verification confirmed")
            } catch {
                log.error("Fail", context: error)
            }
        }
    }

    func cancel(with code: MXTransactionCancelCode) {
        cancel(with: code, success: {}, failure: { _ in })
    }

    func cancel(
        with code: MXTransactionCancelCode,
        success: @escaping () -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.debug("->")
        guard let result = qrCode.cancel(cancelCode: code.value) else {
            log.failure("Cannot cancel transcation")
            failure(Error.cannotCancel)
            return
        }
        
        Task {
            do {
                try await handler.handleOutgoingVerificationRequest(result)
                log.debug("Transaction cancelled")
                await MainActor.run {
                    success()
                }
            } catch {
                log.error("Failed cancelling transaction", context: error)
                await MainActor.run {
                    failure(error)
                }
            }
        }
    }
}

extension QrCodeProtocol {
    var state: MXQRCodeTransactionState {
        // State as enum will be moved to MatrixSDKCrypto in the future
        // to avoid the mapping of booleans into state
        if isDone() {
            return .verified
        } else if isCancelled() {
            return .cancelled
        } else if hasBeenScanned() {
            return .qrScannedByOther
        } else if weStarted() {
            return .waitingOtherConfirm
        }
        return .unknown
    }
}

#endif

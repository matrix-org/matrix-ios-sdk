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

/// QR transaction originating from `MatrixSDKCrypto`
class MXQRCodeTransactionV2: NSObject, MXQRCodeTransaction {
    enum QrKind {
        case placeholder
        case code(QrCodeProtocol)
    }
    
    enum Error: Swift.Error {
        case cannotCancel
    }
    
    private(set) var state: MXQRCodeTransactionState = .unknown {
        didSet {
            guard state != oldValue else {
                return
            }
            
            log.debug("\(oldValue.description) -> \(state.description)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .MXKeyVerificationTransactionDidChange, object: self)
            }
        }
    }

    let transactionId: String
    var transport: MXKeyVerificationTransport
    let isIncoming: Bool
    
    let otherUserId: String
    let otherDeviceId: String
    
    var qrCodeData: MXQRCodeData? {
        guard case .code(let qrCode) = qr else {
            log.debug("We do not have QR code, awaiting theirs")
            return nil
        }
        
        guard let code = qrCode.generateQrCode() else {
            log.error("Cannot generate QR code")
            return nil
        }
        let data = MXBase64Tools.data(fromBase64: code)
        return MXQRCodeDataCoder().decode(data)
    }
    
    private(set) var reasonCancelCode: MXTransactionCancelCode?
    let error: Swift.Error?
    
    let dmRoomId: String?
    let dmEventId: String?

    private let request: VerificationRequestProtocol
    private var qr: QrKind
    private let handler: MXCryptoVerifying
    private let log = MXNamedLog(name: "MXQRCodeTransactionV2")

    init(
        request: VerificationRequestProtocol,
        qr: QrKind,
        isIncoming: Bool,
        handler: MXCryptoVerifying
    ) {
        self.request = request
        self.qr = qr
        self.handler = handler
        
        self.transactionId = request.flowId()
        self.transport = request.roomId() != nil ? .directMessage : .toDevice
        self.isIncoming = isIncoming
        self.otherUserId = request.otherUserId()
        self.otherDeviceId = request.otherDeviceId() ?? ""
        self.error = nil
        self.dmRoomId = request.roomId()
        self.dmEventId = request.roomId() != nil ? request.flowId() : nil
        
        super.init()
        
        if case .code(let code) = self.qr {
            code.setChangesListener(listener: self)
        }
    }

    func userHasScannedOtherQrCodeData(_ otherQRCodeData: MXQRCodeData) {
        log.debug("->")
        
        let data = MXQRCodeDataCoder().encode(otherQRCodeData)
        let string = MXBase64Tools.unpaddedBase64(from: data)
        guard let result = request.scanQrCode(data: string) else {
            log.failure("Failed scanning QR code")
            return
        }
        
        Task {
            do {
                try await handler.handleOutgoingVerificationRequest(result.request)
                log.debug("Scanned QR code")
                await MainActor.run {
                    self.qr = .code(result.qr)
                    result.qr.setChangesListener(listener: self)
                }
            } catch {
                log.error("Failed scanning QR code", context: error)
            }
        }
    }

    func otherUserScannedMyQrCode(_ otherUserScanned: Bool) {
        guard case .code(let qrCode) = qr else {
            log.failure("Incorrect kind of QR")
            return
        }
        
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
        guard state != .cancelled && state != .cancelledByMe else {
            log.error("Transaction is already cancelled")
            success()
            return
        }
        
        log.debug("->")
        guard let result = cancellationRequest(with: code) else {
            log.error("Cannot cancel transcation")
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
    
    private func cancellationRequest(with code: MXTransactionCancelCode) -> OutgoingVerificationRequest? {
        switch qr {
        case .code(let qrCode):
            return qrCode.cancel(cancelCode: code.value)
        case .placeholder:
            return request.cancel()
        }
    }
}

extension MXQRCodeTransactionV2: QrCodeListener {
    func onChange(state: QrCodeState) {
        log.debug("\(state)")
        
        switch state {
        case .started:
            self.state = .unknown
        case .scanned:
            self.state = .qrScannedByOther
        case .confirmed:
            self.state = .scannedOtherQR
        case .reciprocated:
            self.state = .waitingOtherConfirm
        case .done:
            self.state = .verified
        case .cancelled(let cancelInfo):
            reasonCancelCode = MXTransactionCancelCode(
                value: cancelInfo.cancelCode,
                humanReadable: cancelInfo.reason
            )
            self.state = cancelInfo.cancelledByUs ? .cancelledByMe : .cancelled
        }
    }
}

private extension MXQRCodeTransactionState {
    var description: String {
        switch self {
        case .unknown:
            return "unknown"
        case .scannedOtherQR:
            return "scannedOtherQR"
        case .waitingOtherConfirm:
            return "waitingOtherConfirm"
        case .qrScannedByOther:
            return "qrScannedByOther"
        case .verified:
            return "verified"
        case .cancelled:
            return "cancelled"
        case .cancelledByMe:
            return "cancelledByMe"
        case .error:
            return "error"
        @unknown default:
            return "unknown"
        }
    }
}

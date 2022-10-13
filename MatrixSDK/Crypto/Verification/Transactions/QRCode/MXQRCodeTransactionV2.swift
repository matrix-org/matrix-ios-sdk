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
    var state: MXQRCodeTransactionState {
        if qrCode.isDone {
            return .verified
        } else if qrCode.isCancelled {
            return .cancelled
        } else if qrCode.otherSideScanned || qrCode.hasBeenConfirmed {
            return .qrScannedByOther
        } else if qrCode.weStarted {
            return .waitingOtherConfirm
        }
        return .unknown
    }
    
    var qrCodeData: MXQRCodeData? {
        do {
            let data = try handler.generateQrCode(userId: otherUserId, flowId: transactionId)
            log.debug("Generated new QR code")
            return MXQRCodeDataCoder().decode(data)
        } catch {
            log.error("Cannot generate QR code", context: error)
            return nil
        }
    }
    
    var transactionId: String {
        return qrCode.flowId
    }
    
    let transport: MXKeyVerificationTransport
    
    var isIncoming: Bool {
        return !qrCode.weStarted
    }
    
    var otherUserId: String {
        return qrCode.otherUserId
    }
    
    var otherDeviceId: String {
        return qrCode.otherDeviceId
    }
    
    var reasonCancelCode: MXTransactionCancelCode? {
        guard let info = qrCode.cancelInfo else {
            return nil
        }
        return .init(
            value: info.cancelCode,
            humanReadable: info.reason
        )
    }
    
    var error: Error? {
        return nil
    }
    
    var dmRoomId: String? {
        return qrCode.roomId
    }
    
    var dmEventId: String? {
        return qrCode.flowId
    }
    
    private var qrCode: QrCode
    private let handler: MXCryptoVerificationHandler
    private let log = MXNamedLog(name: "MXQRCodeTransactionV2")
    
    init(qrCode: QrCode, transport: MXKeyVerificationTransport, handler: MXCryptoVerificationHandler) {
        self.qrCode = qrCode
        self.transport = transport
        self.handler = handler
    }
    
    func userHasScannedOtherQrCodeData(_ otherQRCodeData: MXQRCodeData) {
        log.debug("->")
        
        let data = MXQRCodeDataCoder().encode(otherQRCodeData)
        Task {
            do {
                let qrCode = try await handler.scanQrCode(userId: otherUserId, flowId: transactionId, data: data)
                await MainActor.run {
                    log.debug("Scanned QR code")
                    self.qrCode = qrCode
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

        log.debug("Confirming verification")
        Task {
            do {
                try await handler.confirmVerification(userId: otherUserId, flowId: transactionId)
                log.debug("Verification confirmed")
            } catch {
                log.error("Fail", context: error)
            }
        }
    }
    
    func cancel(with code: MXTransactionCancelCode) {
        cancel(with: code, success: {}, failure: { _ in })
    }
    
    func cancel(with code: MXTransactionCancelCode, success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        log.debug("Cancelling transaction")
        Task {
            do {
                try await handler.cancelVerification(userId: otherUserId, flowId: transactionId, cancelCode: code.value)
                await MainActor.run {
                    log.debug("Transaction cancelled")
                    success()
                }
            } catch {
                await MainActor.run {
                    log.error("Failed cancelling transaction", context: error)
                    failure(error)
                }
            }
        }
    }
}

extension MXQRCodeTransactionV2: MXKeyVerificationTransactionV2 {
    func processUpdates() -> MXKeyVerificationUpdateResult {
        guard
            let verification = handler.verification(userId: otherUserId, flowId: transactionId),
            case .qrCodeV1(let qrCode) = verification
        else {
            log.debug("Transaction was removed")
            return .removed
        }
        
        guard self.qrCode != qrCode else {
            return .noUpdates
        }
        
        log.debug("Transaction was updated - \(qrCode)")
        self.qrCode = qrCode
        return .updated
    }
}

#endif

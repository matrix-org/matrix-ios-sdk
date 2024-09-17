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

/// SAS transaction originating from `MatrixSDKCrypto`
class MXSASTransactionV2: NSObject, MXSASTransaction {
    enum Error: Swift.Error {
        case cannotCancel
    }
    
    private(set) var state: MXSASTransactionState = MXSASTransactionStateUnknown {
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
    let transport: MXKeyVerificationTransport
    let isIncoming: Bool
    
    let otherUserId: String
    let otherDeviceId: String
    
    private(set) var sasEmoji: [MXEmojiRepresentation]?
    private(set) var sasDecimal: String?
    
    private(set) var reasonCancelCode: MXTransactionCancelCode?
    let error: Swift.Error?
    
    let dmRoomId: String?
    let dmEventId: String?
    
    private let sas: SasProtocol
    private let handler: MXCryptoVerifying
    private let log = MXNamedLog(name: "MXSASTransactionV2")
    
    init(sas: SasProtocol, isIncoming: Bool, handler: MXCryptoVerifying) {
        self.sas = sas
        self.handler = handler
        
        self.transactionId = sas.flowId()
        self.transport = sas.roomId() != nil ?.directMessage : .toDevice
        self.isIncoming = isIncoming
        self.otherUserId = sas.otherUserId()
        self.otherDeviceId = sas.otherDeviceId()
        self.error = nil
        self.dmRoomId = sas.roomId()
        self.dmEventId = sas.roomId() != nil ? sas.flowId() : nil
        
        super.init()
        
        sas.setChangesListener(listener: self)
    }
    
    func accept() {
        log.debug("->")
        guard let outgoingRequest = sas.accept() else {
            log.error("Cannot accept transaction")
            return 
        }
        
        Task {
            do {
                try await handler.handleOutgoingVerificationRequest(outgoingRequest)
                log.debug("Accepted transaction")
            } catch {
                log.error("Cannot accept transaction", context: error)
            }
        }
    }
    
    func confirmSASMatch() {
        log.debug("->")
        Task {
            do {
                guard let result = try sas.confirm() else {
                    log.error("Cannot confirm transaction")
                    return
                }
                try await handler.handleVerificationConfirmation(result)
                log.debug("Confirmed transaction match")
            } catch {
                log.error("Cannot confirm transaction", context: error)
            }
        }
    }
    
    func cancel(with code: MXTransactionCancelCode) {
        cancel(with: code) {
            // No-op
        } failure: { [weak self] in
            self?.log.error("Cannot cancel transaction", context: $0)
        }
    }
    
    func cancel(
        with code: MXTransactionCancelCode,
        success: @escaping () -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.debug("->")
        guard let outgoingRequest = sas.cancel(cancelCode: code.value) else {
            log.error("Cannot cancel")
            failure(Error.cannotCancel)
            return
        }
        
        Task {
            do {
                try await handler.handleOutgoingVerificationRequest(outgoingRequest)
                log.debug("Cancelled transaction")
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

extension MXSASTransactionV2: SasListener {
    func onChange(state: SasState) {
        log.debug("\(state)")
        
        switch state {
        case .started:
            self.state = MXSASTransactionStateIncomingShowAccept
        case .accepted:
            self.state = MXSASTransactionStateWaitForPartnerKey
        case .keysExchanged(let emojis, let decimals):
            let representations = MXLegacySASTransaction.allEmojiRepresentations()
            sasEmoji = emojis?.compactMap { idx in
                idx < representations.count ? representations[Int(idx)] : nil
            }
            sasDecimal = decimals.map(String.init).joined(separator: " ")
            
            self.state = MXSASTransactionStateShowSAS
            
        case .confirmed:
            self.state = MXSASTransactionStateWaitForPartnerToConfirm
        case .done:
            self.state = MXSASTransactionStateVerified
        case .cancelled(let cancelInfo):
            reasonCancelCode = MXTransactionCancelCode(
                value: cancelInfo.cancelCode,
                humanReadable: cancelInfo.reason
            )
            self.state = cancelInfo.cancelledByUs == true ? MXSASTransactionStateCancelledByMe : MXSASTransactionStateCancelled
        case .created:
            self.state = MXSASTransactionStateOutgoingWaitForPartnerToAccept
        }
    }
}

extension MXSASTransactionState {
    var description: String {
        switch self {
        case MXSASTransactionStateUnknown:
            return "unknown"
        case MXSASTransactionStateIncomingShowAccept:
            return "incomingShowAccept"
        case MXSASTransactionStateOutgoingWaitForPartnerToAccept:
            return "outgoingWaitForPartnerToAccept"
        case MXSASTransactionStateWaitForPartnerKey:
            return "waitForPartnerKey"
        case MXSASTransactionStateShowSAS:
            return "showSAS"
        case MXSASTransactionStateWaitForPartnerToConfirm:
            return "waitForPartnerToConfirm"
        case MXSASTransactionStateVerified:
            return "verified"
        case MXSASTransactionStateCancelled:
            return "cancelled"
        case MXSASTransactionStateCancelledByMe:
            return "cancelledByMe"
        case MXSASTransactionStateError:
            return "error"
        default:
            return "unknown"
        }
    }
}


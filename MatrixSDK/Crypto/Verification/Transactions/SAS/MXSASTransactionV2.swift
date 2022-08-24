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

/// SAS transaction originating from `MatrixSDKCrypto`
class MXSASTransactionV2: NSObject, MXSASTransaction {
    typealias GetEmojisAction = (Sas) -> [MXEmojiRepresentation]
    typealias ConfirmMatchAction = (MXSASTransaction) -> Void
    typealias CancelAction = (MXSASTransaction, MXTransactionCancelCode) -> Void
    
    var state: MXSASTransactionState {
        // State as enum will be moved to MatrixSDKCrypto in the future
        // to avoid the mapping of booleans into state
        if sas.isDone {
            return MXSASTransactionStateVerified
        } else if sas.isCancelled {
            return MXSASTransactionStateCancelled
        } else if sas.canBePresented {
            return MXSASTransactionStateShowSAS
        } else if sas.hasBeenAccepted && !sas.haveWeConfirmed {
            return MXSASTransactionStateIncomingShowAccept
        } else if sas.haveWeConfirmed {
            return MXSASTransactionStateOutgoingWaitForPartnerToAccept
        }
        return MXSASTransactionStateUnknown
    }
    
    var sasEmoji: [MXEmojiRepresentation]? {
        return getEmojisAction(sas)
    }
    
    var sasDecimal: String? {
        log.debug("Not implemented")
        return nil
    }
    
    var transactionId: String {
        return sas.flowId
    }
    
    var transport: MXKeyVerificationTransport {
        log.debug("Not fully implemented")
        return .directMessage
    }
    
    var isIncoming: Bool {
        return !sas.weStarted
    }
    
    var otherUserId: String {
        return sas.otherUserId
    }
    
    var otherDeviceId: String {
        return sas.otherDeviceId
    }
    
    var reasonCancelCode: MXTransactionCancelCode? {
        guard let info = sas.cancelInfo else {
            return nil
        }
        return MXTransactionCancelCode(
            value: info.cancelCode,
            humanReadable: info.reason
        )
    }
    
    var error: Error? {
        return nil
    }

    var dmRoomId: String? {
        return sas.roomId
    }

    var dmEventId: String? {
        return transactionId
    }
    
    private var sas: Sas
    private let getEmojisAction: GetEmojisAction
    private let confirmMatchAction: ConfirmMatchAction
    private let cancelAction: CancelAction
    
    private let log = MXNamedLog(name: "MXSASTransactionV2")
    
    init(
        sas: Sas,
        getEmojisAction: @escaping GetEmojisAction,
        confirmMatchAction: @escaping ConfirmMatchAction,
        cancelAction: @escaping CancelAction
    ) {
        self.sas = sas
        self.getEmojisAction = getEmojisAction
        self.confirmMatchAction = confirmMatchAction
        self.cancelAction = cancelAction
    }
    
    func update(sas: Sas) {
        guard self.sas != sas else {
            return
        }
        self.sas = sas
        NotificationCenter.default.post(name: .MXKeyVerificationTransactionDidChange, object: self)
    }
    
    func confirmSASMatch() {
        confirmMatchAction(self)
    }
    
    func cancel(with code: MXTransactionCancelCode) {
        cancelAction(self, code)
    }
    
    func cancel(with code: MXTransactionCancelCode, success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        cancelAction(self, code)
        success()
    }
}

#endif

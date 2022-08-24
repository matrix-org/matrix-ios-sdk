//
//  MXKeyVerificationManagerV2.swift
//  MatrixSDK
//
//  Created by Element on 05/07/2022.
//

import Foundation

#if DEBUG && os(iOS)

import MatrixSDKCrypto

@available(iOS 13.0.0, *)
class MXKeyVerificationManagerV2: MXKeyVerificationManager {
    typealias GetOrCreateDMRoomId = (_ userId: String) async throws -> String
    
    override var requestTimeout: TimeInterval {
        set {
            log.debug("Not implemented")
        }
        get {
            log.debug("Not implemented")
            return 1000
        }
    }
    
    private let verification: MXCryptoVerification
    private let getOrCreateDMRoomId: GetOrCreateDMRoomId
    
    private var requests: [MXKeyVerificationRequestV2]
    private var transactions: [MXSASTransactionV2]
    
    private let log = MXNamedLog(name: "MXKeyVerificationManagerV2")
    
    init(verification: MXCryptoVerification, getOrCreateDMRoomId: @escaping GetOrCreateDMRoomId) {
        self.verification = verification
        self.getOrCreateDMRoomId = getOrCreateDMRoomId
        
        self.requests = []
        self.transactions = []
        
        super.init()
    }
    
    func updatePendingRequests() {
        for request in requests {
            guard let req = verification.verificationRequest(userId: request.otherUser, flowId: request.requestId) else {
                log.debug("No request found for id \(request.requestId)")
                continue
            }
            request.update(request: req)
        }
        
        for transaction in transactions {
            guard let verification = verification.verification(userId: transaction.otherUserId, flowId: transaction.transactionId) else {
                log.debug("No transaction found for id \(transaction.transactionId)")
                continue
            }
            guard case .sasV1(let sas) = verification else {
                assertionFailure("Not implemented")
                continue
            }
            transaction.update(sas: sas)
        }
    }
    
    override func requestVerificationByToDevice(
        withUserId userId: String,
        deviceIds: [String]?,
        methods: [String],
        success: @escaping (MXKeyVerificationRequest) -> Void,
        failure: @escaping (Error) -> Void
    ) {
        log.debug("Not implemented")
        success(MXDefaultKeyVerificationRequest())
    }
    
    override func requestVerificationByDM(
        withUserId userId: String,
        roomId: String?,
        fallbackText: String,
        methods: [String],
        success: @escaping (MXKeyVerificationRequest) -> Void,
        failure: @escaping (Error) -> Void
    ) {
        Task {
            do {
                let roomId = try await getOrCreateDMRoomId(userId)
                let req = try await verification.requestVerification(
                    userId: userId,
                    roomId: roomId,
                    methods: methods
                )
                let request = MXKeyVerificationRequestV2(request: req) { [weak self] request, code in
                    self?.cancel(request: request, code: code)
                }
                requests.append(request)
                await MainActor.run {
                    success(request)
                }
            } catch {
                log.error("Cannot request verification", context: error)
                await MainActor.run {
                    failure(error)
                }
            }
        }
    }
    
    override var pendingRequests: [MXKeyVerificationRequest] {
        return requests
    }
    
    override func beginKeyVerification(
        withUserId userId: String,
        andDeviceId deviceId: String,
        method: String,
        success: @escaping (MXKeyVerificationTransaction) -> Void,
        failure: @escaping (Error) -> Void
    ) {
        log.debug("Not implemented")
        success(MXDefaultKeyVerificationTransaction())
    }
    
    override func beginKeyVerification(
        from request: MXKeyVerificationRequest,
        method: String,
        success: @escaping (MXKeyVerificationTransaction) -> Void,
        failure: @escaping (Error) -> Void
    ) {
        Task {
            do {
                let sas = try await verification.beginSasVerification(userId: request.otherUser, flowId: request.requestId)
                let transaction = MXSASTransactionV2(
                    sas: sas,
                    getEmojisAction: { [weak self] in
                        self?.getEmojis(sas: $0) ?? []
                    },
                    confirmMatchAction: { [weak self] in
                        self?.confirm(transaction: $0)
                    },
                    cancelAction: { [weak self] in
                        self?.cancel(transaction: $0, code: $1)
                    }
                )
                transactions.append(transaction)
                
                await MainActor.run {
                    success(transaction)
                }
            } catch {
                MXLog.error("[MXKeyVerificationRequestV2] error", context: error)
                await MainActor.run {
                    failure(error)
                }
            }
        }
    }
    
    override func transactions(_ complete: @escaping ([MXKeyVerificationTransaction]) -> Void) {
        complete(transactions)
    }
    
    override func keyVerification(
        fromKeyVerificationEvent event: MXEvent,
        success: @escaping (MXKeyVerification) -> Void,
        failure: @escaping (Error) -> Void
    ) -> MXHTTPOperation? {
        log.debug("Not implemented")
        success(MXKeyVerification())
        return MXHTTPOperation()
    }
    
    override func keyVerificationId(fromDMEvent event: MXEvent) -> String? {
        log.debug("Not implemented")
        return nil
    }
    
    override func qrCodeTransaction(withTransactionId transactionId: String) -> MXQRCodeTransaction? {
        log.debug("Not implemented")
        return nil
    }
    
    override func removeQRCodeTransaction(withTransactionId transactionId: String) {
        log.debug("Not implemented")
    }
    
    override func notifyOthersOfAcceptance(withTransactionId transactionId: String, acceptedUserId: String, acceptedDeviceId: String, success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        log.debug("Not implemented")
        success()
    }
    
    private func getEmojis(sas: Sas) -> [MXEmojiRepresentation] {
        do {
            let indices = try verification.emojiIndexes(sas: sas)
            let emojis = MXDefaultSASTransaction.allEmojiRepresentations()
            return indices.compactMap { idx in
                idx < emojis.count ? emojis[idx] : nil
            }
        } catch {
            log.error("Cannot get emoji indices", context: error)
            return []
        }
    }
    
    private func cancel(request: MXKeyVerificationRequest, code: MXTransactionCancelCode) {
        Task {
            do {
                try await verification.cancelVerification(userId: request.otherUser, flowId: request.requestId, cancelCode: code.value)
            } catch {
                log.error("Cannot cancel request", context: error)
            }
        }
    }
    
    private func confirm(transaction: MXSASTransaction) {
        Task {
            do {
                try await verification.confirmVerification(userId: transaction.otherUserId, flowId: transaction.transactionId)
            } catch {
                log.error("Cannot confirm transaction", context: error)
            }
        }
    }
    
    private func cancel(transaction: MXSASTransaction, code: MXTransactionCancelCode) {
        Task {
            do {
                try await verification.cancelVerification(userId: transaction.otherUserId, flowId: transaction.transactionId, cancelCode: code.value)
            } catch {
                log.error("Cannot cancel request", context: error)
            }
        }
    }
}

#endif

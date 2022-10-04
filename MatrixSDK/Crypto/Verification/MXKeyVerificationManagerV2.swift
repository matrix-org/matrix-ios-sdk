//
//  MXKeyVerificationManagerV2.swift
//  MatrixSDK
//
//  Created by Element on 05/07/2022.
//

import Foundation

#if DEBUG && os(iOS)

import MatrixSDKCrypto

/// Result of processing updates on verification object (request or transaction)
/// after each sync loop
enum MXKeyVerificationUpdateResult {
    // The object has not changed since last sync
    case noUpdates
    // The object's state has changed
    case updated
    // The object is no longer available (e.g. it was cancelled)
    case removed
}

typealias MXCryptoVerification = MXCryptoVerificationRequesting & MXCryptoSASVerifying

class MXKeyVerificationManagerV2: MXKeyVerificationManager {
    enum Error: Swift.Error {
        case notSupported
    }
    
    typealias GetOrCreateDMRoomId = (_ userId: String) async throws -> String
    
    private let verification: MXCryptoVerification
    private let getOrCreateDMRoomId: GetOrCreateDMRoomId
    
    // We need to keep track of request / transaction objects by reference
    // because various flows / screens subscribe to updates via global notifications
    // posted through them
    private var activeRequests: [String: MXKeyVerificationRequestV2]
    private var activeTransactions: [String: MXSASTransactionV2]
    
    private let log = MXNamedLog(name: "MXKeyVerificationManagerV2")
    
    init(verification: MXCryptoVerification, getOrCreateDMRoomId: @escaping GetOrCreateDMRoomId) {
        self.verification = verification
        self.getOrCreateDMRoomId = getOrCreateDMRoomId
        
        self.activeRequests = [:]
        self.activeTransactions = [:]
        
        super.init()
    }
    
    func handleDeviceEvents(_ events: [MXEvent]) {
        // We only have to manually handle request and start events,
        // because they require creation of new objects observed by the UI.
        // The other events (e.g. cancellation) are handled automatically
        // by `MXCryptoVerification`
        let eventTypes: Set<String> = [
            kMXMessageTypeKeyVerificationRequest,
            kMXEventTypeStringKeyVerificationStart
        ]
        
        for event in events {
            guard eventTypes.contains(event.type) else {
                continue
            }
            
            guard
                let userId = event.sender,
                let flowId = event.content["transaction_id"] as? String
            else {
                log.error("Missing userId or flowId in event")
                continue
            }
            
            log.debug("Processing incoming verification event")
            switch event.type {
            case kMXMessageTypeKeyVerificationRequest:
                incomingVerificationRequest(userId: userId, flowId: flowId)
            case kMXEventTypeStringKeyVerificationStart:
                incomingVerificationStart(userId: userId, flowId: flowId)
            default:
                log.failure("Event type should not be handled by key verification", context: event.type)
            }
        }
        
        updatePendingVerification()
    }
    
    override func requestVerificationByToDevice(
        withUserId userId: String,
        deviceIds: [String]?,
        methods: [String],
        success: @escaping (MXKeyVerificationRequest) -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        guard userId == verification.userId else {
            log.failure("To-device verification with other users is not supported")
            failure(Error.notSupported)
            return
        }
        
        log.debug("Requesting verification by to-device")
        Task {
            do {
                let req = try await verification.requestSelfVerification(methods: methods)
                
                let request = addRequest(for: req, transport: .toDevice)
                await MainActor.run {
                    log.debug("Request successfully sent")
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
    
    override func requestVerificationByDM(
        withUserId userId: String,
        roomId: String?,
        fallbackText: String,
        methods: [String],
        success: @escaping (MXKeyVerificationRequest) -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.debug("Requesting verification by DM")
        Task {
            do {
                let roomId = try await getOrCreateDMRoomId(userId)
                let req = try await verification.requestVerification(
                    userId: userId,
                    roomId: roomId,
                    methods: methods
                )
                
                let request = addRequest(for: req, transport: .directMessage)
                await MainActor.run {
                    log.debug("Request successfully sent")
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
    
    override func beginKeyVerification(
        withUserId userId: String,
        andDeviceId deviceId: String,
        method: String,
        success: @escaping (MXKeyVerificationTransaction) -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.debug("Not implemented")
        success(MXDefaultKeyVerificationTransaction())
    }
    
    override func beginKeyVerification(
        from request: MXKeyVerificationRequest,
        method: String,
        success: @escaping (MXKeyVerificationTransaction) -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.debug("Starting \(method) verification flow")
        Task {
            do {
                let sas = try await verification.startSasVerification(userId: request.otherUser, flowId: request.requestId)
                let transaction = addSasTransaction(for: sas, transport: request.transport)
                
                await MainActor.run {
                    log.debug("Created verification transaction")
                    success(transaction)
                }
            } catch {
                log.error("Failed creating verification transaction", context: error)
                await MainActor.run {
                    failure(error)
                }
            }
        }
    }
    
    override var pendingRequests: [MXKeyVerificationRequest] {
        return Array(activeRequests.values)
    }
    
    override func transactions(_ complete: @escaping ([MXKeyVerificationTransaction]) -> Void) {
        complete(Array(activeTransactions.values))
    }
    
    override func keyVerification(
        fromKeyVerificationEvent event: MXEvent,
        success: @escaping (MXKeyVerification) -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) -> MXHTTPOperation? {
        log.debug("Not implemented")
        success(MXKeyVerification())
        return MXHTTPOperation()
    }

    override func qrCodeTransaction(withTransactionId transactionId: String) -> MXQRCodeTransaction? {
        log.debug("Not implemented")
        return nil
    }
    
    override func removeQRCodeTransaction(withTransactionId transactionId: String) {
        log.debug("Not implemented")
    }
    
    override func notifyOthersOfAcceptance(withTransactionId transactionId: String, acceptedUserId: String, acceptedDeviceId: String, success: @escaping () -> Void, failure: @escaping (Swift.Error) -> Void) {
        log.debug("Not implemented")
        success()
    }
    
    // MARK: - Private
    
    private func incomingVerificationRequest(userId: String, flowId: String) {
        guard let request = verification.verificationRequest(userId: userId, flowId: flowId) else {
            log.error("Verification request is not known", context: [
                "flow_id": flowId
            ])
            return
        }
        
        _ = addRequest(for: request, transport: .toDevice, notify: true)
    }
    
    private func incomingVerificationStart(userId: String, flowId: String) {
        guard let verif = verification.verification(userId: userId, flowId: flowId) else {
            log.error("Verification is not known", context: [
                "flow_id": flowId
            ])
            return
        }
        
        switch verif {
        case .sasV1(let sas):
            let transaction = addSasTransaction(for: sas, transport: .toDevice)
            transaction.accept()
            
        case .qrCodeV1:
            assertionFailure("Not implemented")
        }
    }
    
    private func updatePendingVerification() {
        for request in activeRequests.values {
            switch request.processUpdates() {
            case .noUpdates:
                break
            case .updated:
                NotificationCenter.default.post(name: .MXKeyVerificationRequestDidChange, object: request)
            case .removed:
                activeRequests[request.requestId] = nil
            }
        }
        
        for transaction in activeTransactions.values {
            switch transaction.processUpdates() {
            case .noUpdates:
                break
            case .updated:
                NotificationCenter.default.post(name: .MXKeyVerificationTransactionDidChange, object: transaction)
            case .removed:
                activeTransactions[transaction.transactionId] = nil
            }
        }
    }
    
    private func addRequest(
        for request: VerificationRequest,
        transport: MXKeyVerificationTransport,
        notify: Bool = false
    ) -> MXKeyVerificationRequestV2 {
        
        let request = MXKeyVerificationRequestV2(
            request: request,
            transport: transport,
            handler: verification
        )
        activeRequests[request.requestId] = request
        
        if notify {
            NotificationCenter.default.post(
                name: .MXKeyVerificationManagerNewRequest,
                object: self,
                userInfo: [
                    MXKeyVerificationManagerNotificationRequestKey: request
                ]
            )
        }
        return request
    }
    
    private func addSasTransaction(for sas: Sas, transport: MXKeyVerificationTransport) -> MXSASTransactionV2 {
        let transaction = MXSASTransactionV2(sas: sas, transport: transport, handler: verification)
        activeTransactions[transaction.transactionId] = transaction
        return transaction
    }
}

extension MXKeyVerificationManagerV2: MXRecoveryServiceDelegate {
    func setUserVerification(_ isTrusted: Bool, forUser: String, success: () -> Void, failure: (Swift.Error) -> Void) {
        log.error("Not implemented")
    }
}

#endif

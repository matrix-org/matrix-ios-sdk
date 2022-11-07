//
//  MXKeyVerificationManagerV2.swift
//  MatrixSDK
//
//  Created by Element on 05/07/2022.
//

import Foundation

#if DEBUG

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

protocol MXKeyVerificationTransactionV2: MXKeyVerificationTransaction {
    func processUpdates() -> MXKeyVerificationUpdateResult
}

typealias MXCryptoVerificationHandler = MXCryptoVerificationRequesting & MXCryptoSASVerifying & MXCryptoQRCodeVerifying

class MXKeyVerificationManagerV2: NSObject, MXKeyVerificationManager {
    enum Error: Swift.Error {
        case methodNotSupported
        case unknownFlowId
        case missingRoom
        case missingDeviceId
    }
    
    // A set of room events we have to monitor manually to synchronize CryptoMachine
    // and verification UI, optionally triggering global notifications.
    static let dmEventTypes: Set<MXEventType> = [
        .roomMessage, // Verification request in DM is wrapped inside `m.room.message`
        .keyVerificationReady,
        .keyVerificationStart,
        .keyVerificationAccept,
        .keyVerificationKey,
        .keyVerificationMac,
        .keyVerificationCancel,
        .keyVerificationDone,
    ]
    
    // A set of to-device events we have to monitor manually to synchronize CryptoMachine
    // and verification UI, optionally triggering global notifications.
    private static let toDeviceEventTypes: Set<String> = [
        kMXMessageTypeKeyVerificationRequest,
        kMXEventTypeStringKeyVerificationStart
    ]
    
    private weak var session: MXSession?
    private let handler: MXCryptoVerificationHandler
    
    // We need to keep track of request / transaction objects by reference
    // because various flows / screens subscribe to updates via global notifications
    // posted through them
    private var activeRequests: [String: MXKeyVerificationRequestV2]
    private var activeTransactions: [String: MXKeyVerificationTransactionV2]
    private let resolver: MXKeyVerificationStateResolver
    
    private let log = MXNamedLog(name: "MXKeyVerificationManagerV2")
    
    init(
        session: MXSession,
        handler: MXCryptoVerificationHandler
    ) {
        self.session = session
        self.handler = handler
        self.activeRequests = [:]
        self.activeTransactions = [:]
        self.resolver = MXKeyVerificationStateResolver(myUserId: session.myUserId, aggregations: session.aggregations)
    }
    
    var pendingRequests: [MXKeyVerificationRequest] {
        return Array(activeRequests.values)
    }
    
    func transactions(_ complete: @escaping ([MXKeyVerificationTransaction]) -> Void) {
        complete(Array(activeTransactions.values))
    }
    
    func requestVerificationByToDevice(
        withUserId userId: String,
        deviceIds: [String]?,
        methods: [String],
        success: @escaping (MXKeyVerificationRequest) -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.debug("->")
        
        Task {
            do {
                let request = try await requestVerificationByToDevice(withUserId: userId, deviceIds: deviceIds, methods: methods)
                await MainActor.run {
                    log.debug("Request successfully sent")
                    success(request)
                }
            } catch {
                await MainActor.run {
                    log.error("Cannot request verification", context: error)
                    failure(error)
                }
            }
        }
    }
    
    func requestVerificationByDM(
        withUserId userId: String,
        roomId: String?,
        fallbackText: String,
        methods: [String],
        success: @escaping (MXKeyVerificationRequest) -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.debug("->")
        Task {
            do {
                let roomId = try await getOrCreateDMRoomId(userId: userId)
                let request = try await requestVerification(
                    userId: userId,
                    roomId: roomId,
                    methods: methods
                )
                await MainActor.run {
                    log.debug("Request successfully sent")
                    success(request)
                }
            } catch {
                await MainActor.run {
                    log.error("Cannot request verification", context: error)
                    failure(error)
                }
            }
        }
    }
    
    func beginKeyVerification(
        from request: MXKeyVerificationRequest,
        method: String,
        success: @escaping (MXKeyVerificationTransaction) -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.debug("Starting \(method) verification flow")
        
        Task {
            do {
                let transaction = try await startSasVerification(userId: request.otherUser, flowId: request.requestId, transport: request.transport)
                await MainActor.run {
                    log.debug("Created verification transaction")
                    success(transaction)
                }
            } catch {
                await MainActor.run {
                    log.error("Failed creating verification transaction", context: error)
                    failure(error)
                }
            }
        }
    }
    
    func keyVerification(
        fromKeyVerificationEvent event: MXEvent,
        roomId: String,
        success: @escaping (MXKeyVerification) -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) -> MXHTTPOperation? {
        guard let flowId = event.relatesTo?.eventId ?? event.eventId else {
            log.failure("Unknown flow id")
            failure(Error.unknownFlowId)
            return nil
        }

        if let request = activeRequests[flowId] {
            log.debug("Using active request")
            
            let result = MXKeyVerification()
            result.request = request
            success(result)
        } else if let request = handler.verificationRequest(userId: event.sender, flowId: flowId) {
            log.debug("Adding pending request")
            
            let result = MXKeyVerification()
            result.request = addRequest(for: request, transport: .directMessage)
            success(result)

        } else {
            log.debug("Computing archived request")

            Task {
                do {
                    // If we do not have active verification anymore (managed by CryptoMachine), it means
                    // we have completed or cancelled request, where the state can be computed from
                    // aggregate events.
                    let result = MXKeyVerification()
                    result.state = try await resolver.verificationState(flowId: flowId, roomId: roomId)
                    await MainActor.run {
                        success(result)
                    }
                } catch {
                    await MainActor.run {
                        failure(error)
                    }
                }
            }
        }
        return nil
    }

    func qrCodeTransaction(withTransactionId transactionId: String) -> MXQRCodeTransaction? {
        if let transaction = activeTransactions[transactionId] as? MXQRCodeTransaction {
            return transaction
        }
        
        guard let request = activeRequests[transactionId] else {
            log.error("There is no pending verification request")
            return nil
        }
        
        do {
            log.debug("Starting new QR verification")
            let qr = try handler.startQrVerification(userId: request.otherUser, flowId: transactionId)
            return addQrTransaction(for: qr, transport: request.transport)
        } catch {
            // We may not be able to start QR verification flow (the other device cannot scan our code)
            // but we might be able to scan theirs, so creating an empty placeholder transaction for this case.
            log.debug("Adding placeholder QR verification")
            let qr = QrCode(
                otherUserId: request.otherUser,
                otherDeviceId: request.otherDevice ?? "",
                flowId: request.requestId,
                roomId: request.roomId,
                weStarted: request.isFromMyDevice,
                otherSideScanned: false,
                hasBeenConfirmed: false,
                reciprocated: false,
                isDone: false,
                isCancelled: false,
                cancelInfo: nil
            )
            return addQrTransaction(for: qr, transport: request.transport)
        }
    }
    
    func removeQRCodeTransaction(withTransactionId transactionId: String) {
        guard activeTransactions[transactionId] is MXQRCodeTransaction else {
            return
        }
        log.debug("Removed QR verification")
        activeTransactions[transactionId] = nil
    }
    
    // MARK: - Events
    
    @MainActor
    func handleDeviceEvent(_ event: MXEvent) {
        guard Self.toDeviceEventTypes.contains(event.type) else {
            updatePendingVerification()
            return
        }
        
        log.debug("->")
        
        guard
            let userId = event.sender,
            let flowId = event.content["transaction_id"] as? String
        else {
            log.error("Missing userId or flowId in event")
            return
        }
        
        switch event.type {
        case kMXMessageTypeKeyVerificationRequest:
            handleIncomingRequest(userId: userId, flowId: flowId, transport: .toDevice)
            
        case kMXEventTypeStringKeyVerificationStart:
            handleIncomingVerification(userId: userId, flowId: flowId, transport: .toDevice)
            
        default:
            log.failure("Event type should not be handled by key verification", context: event.type)
        }
        
        updatePendingVerification()
    }
    
    @MainActor
    func handleRoomEvent(_ event: MXEvent) -> String? {
        guard isRoomVerificationEvent(event) else {
            return nil
        }
        
        if !event.isEncrypted, let roomId = event.roomId {
            handler.receiveUnencryptedVerificationEvent(event: event, roomId: roomId)
            updatePendingVerification()
        }
        
        if event.type == kMXEventTypeStringRoomMessage && event.content?[kMXMessageTypeKey] as? String == kMXMessageTypeKeyVerificationRequest {
            handleIncomingRequest(userId: event.sender, flowId: event.eventId, transport: .directMessage)
            return event.sender
            
        } else if event.type == kMXEventTypeStringKeyVerificationStart, let flowId = event.relatesTo.eventId {
            handleIncomingVerification(userId: event.sender, flowId: flowId, transport: .directMessage)
            return event.sender
        } else {
            return nil
        }
    }
    
    // MARK: - Update
    
    @MainActor
    func updatePendingVerification() {
        if !activeRequests.isEmpty {
            log.debug("Processing \(activeRequests.count) pending requests")
        }

        for request in activeRequests.values {
            switch request.processUpdates() {
            case .noUpdates:
                break
            case .updated:
                NotificationCenter.default.post(name: .MXKeyVerificationRequestDidChange, object: request)
            case .removed:
                NotificationCenter.default.post(name: .MXKeyVerificationRequestDidChange, object: request)
                activeRequests[request.requestId] = nil
            }
        }

        if !activeTransactions.isEmpty {
            log.debug("Processing \(activeTransactions.count) pending transactions")
        }

        for transaction in activeTransactions.values {
            switch transaction.processUpdates() {
            case .noUpdates:
                break
            case .updated:
                NotificationCenter.default.post(name: .MXKeyVerificationTransactionDidChange, object: transaction)
            case .removed:
                NotificationCenter.default.post(name: .MXKeyVerificationTransactionDidChange, object: transaction)
                activeTransactions[transaction.transactionId] = nil
            }
        }
    }
    
    // MARK: - Verification requests
    
    func requestVerificationByToDevice(
        withUserId userId: String,
        deviceIds: [String]?,
        methods: [String]
    ) async throws -> MXKeyVerificationRequest {
        log.debug("->")
        
        if userId == session?.myUserId {
            log.debug("Self-verification")
            return try await requestSelfVerification(methods: methods)
        } else if let deviceId = deviceIds?.first {
            log.debug("Direct verification of another device")
            if let count = deviceIds?.count, count > 1 {
                log.error("Verifying more than one device at once is not supported")
            }
            return try await requestVerification(userId: userId, deviceId: deviceId, methods: methods)
        } else {
            throw Error.missingDeviceId
        }
    }
    
    private func requestVerification(userId: String, roomId: String, methods: [String]) async throws -> MXKeyVerificationRequest {
        log.debug("->")
        
        let request = try await handler.requestVerification(
            userId: userId,
            roomId: roomId,
            methods: methods
        )
        return addRequest(for: request, transport: .directMessage)
    }
    
    private func requestVerification(userId: String, deviceId: String, methods: [String]) async throws -> MXKeyVerificationRequest {
        log.debug("->")
        
        let request = try await handler.requestVerification(
            userId: userId,
            deviceId: deviceId,
            methods: methods
        )
        return addRequest(for: request, transport: .toDevice)
    }
    
    private func requestSelfVerification(methods: [String]) async throws -> MXKeyVerificationRequest {
        log.debug("->")

        let request = try await handler.requestSelfVerification(methods: methods)
        return addRequest(for: request, transport: .directMessage)
    }
    
    private func handleIncomingRequest(userId: String, flowId: String, transport: MXKeyVerificationTransport) {
        log.debug(flowId)
        
        guard activeRequests[flowId] == nil else {
            log.debug("Request already known, ignoring")
            return
        }
        
        guard let req = handler.verificationRequest(userId: userId, flowId: flowId) else {
            log.error("Verification request is not known", context: [
                "flow_id": flowId
            ])
            return
        }

        log.debug("Tracking new verification request")
        
        _ = addRequest(for: req, transport: transport, notify: true)
    }
    
    private func addRequest(
        for request: VerificationRequest,
        transport: MXKeyVerificationTransport,
        notify: Bool = false
    ) -> MXKeyVerificationRequestV2 {
        let request = MXKeyVerificationRequestV2(
            request: request,
            transport: transport,
            handler: handler
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
            NotificationCenter.default.post(
                name: .MXKeyVerificationRequestDidChange,
                object: request
            )
        }
        return request
    }
    
    // MARK: - Verification transactions
    
    private func startSasVerification(userId: String, flowId: String, transport: MXKeyVerificationTransport) async throws -> MXKeyVerificationTransaction {
        log.debug("->")
        let sas = try await handler.startSasVerification(userId: userId, flowId: flowId)
        return addSasTransaction(for: sas, transport: transport)
    }
    
    private func handleIncomingVerification(userId: String, flowId: String, transport: MXKeyVerificationTransport) {
        log.debug(flowId)
        
        guard let verification = handler.verification(userId: userId, flowId: flowId) else {
            log.error("Verification is not known", context: [
                "flow_id": flowId
            ])
            return
        }

        switch verification {
        case .sasV1(let sas):
            log.debug("Tracking new SAS verification transaction")
            let transaction = addSasTransaction(for: sas, transport: transport, notify: true)
            if activeRequests[transaction.transactionId] != nil {
                log.debug("Auto-accepting transaction that matches a pending request")
                transaction.accept()
                Task {
                    await updatePendingVerification()
                }
            }
            
        case .qrCodeV1(let qrCode):
            if activeTransactions[flowId] is MXQRCodeTransaction {
                // This flow may happen if we have previously started a QR verification, but so has the other side,
                // and we scanned their code which now takes over the verification flow
                log.debug("Updating existing QR verification transaction")
                Task {
                    await updatePendingVerification()
                }
            } else {
                log.debug("Tracking new QR verification transaction")
                _ = addQrTransaction(for: qrCode, transport: transport)
            }
        }
    }
    
    private func addSasTransaction(
        for sas: Sas,
        transport: MXKeyVerificationTransport,
        notify: Bool = false
    ) -> MXSASTransactionV2 {
        let transaction = MXSASTransactionV2(
            sas: sas,
            transport: transport,
            handler: handler
        )
        activeTransactions[transaction.transactionId] = transaction
        if notify {
            NotificationCenter.default.post(
                name: .MXKeyVerificationManagerNewTransaction,
                object: self,
                userInfo: [
                    MXKeyVerificationManagerNotificationTransactionKey: transaction
                ]
            )
            NotificationCenter.default.post(
                name: .MXKeyVerificationTransactionDidChange,
                object: transaction
            )
        }
        return transaction
    }
    
    private func addQrTransaction(
        for qrCode: QrCode,
        transport: MXKeyVerificationTransport
    ) -> MXQRCodeTransactionV2 {
        let transaction = MXQRCodeTransactionV2(
            qrCode: qrCode,
            transport: transport,
            handler: handler
        )
        activeTransactions[transaction.transactionId] = transaction
        return transaction
    }
    
    // MARK: - Helpers
    
    private func getOrCreateDMRoomId(userId: String) async throws -> String {
        guard let session = session else {
            log.error("Session not available")
            throw MXSession.Error.missingRoom
        }
        let room = try await session.getOrCreateDirectJoinedRoom(with: userId)
        guard let roomId = room.roomId else {
            log.failure("Missing room id")
            throw MXSession.Error.missingRoom
        }
        return roomId
    }
    
    private func isRoomVerificationEvent(_ event: MXEvent) -> Bool {
        // Filter incoming events by allowed list of event types
        guard Self.dmEventTypes.contains(where: { $0.identifier == event.type }) else {
            return false
        }
        
        // If it isn't a room message, it must be one of the direction verification events
        guard event.type == MXEventType.roomMessage.identifier else {
            return true
        }
        
        // If the event does not have a message type, it cannot be accepted
        guard let messageType = event.content[kMXMessageTypeKey] as? String else {
            return false
        }
        
        // Only requests are wrapped inside `m.room.message` types
        return messageType == kMXMessageTypeKeyVerificationRequest
    }
}

#endif

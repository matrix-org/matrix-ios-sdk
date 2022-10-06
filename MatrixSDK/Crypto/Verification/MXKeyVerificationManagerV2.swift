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

typealias MXCryptoVerificationHandler = MXCryptoVerificationRequesting & MXCryptoSASVerifying

class MXKeyVerificationManagerV2: NSObject, MXKeyVerificationManager {
    enum Error: Swift.Error {
        case methodNotSupported
        case unknownFlowId
        case missingRoom
    }
    
    // A set of room events we have to monitor manually to synchronize CryptoMachine
    // and verification UI, optionally triggering global notifications.
    private static let dmEventTypes: Set<MXEventType> = [
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
    private var observer: Any?
    
    private let handler: MXCryptoVerificationHandler
    
    // We need to keep track of request / transaction objects by reference
    // because various flows / screens subscribe to updates via global notifications
    // posted through them
    private var activeRequests: [String: MXKeyVerificationRequestV2]
    private var activeTransactions: [String: MXSASTransactionV2]
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
        
        super.init()
        
        listenToRoomEvents(in: session)
    }
    
    deinit {
        session?.removeListener(observer)
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
        
        guard userId == session?.myUserId else {
            log.failure("To-device verification with other users is not supported")
            failure(Error.methodNotSupported)
            return
        }
        
        Task {
            do {
                let request = try await requestSelfVerification(methods: methods)
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
        withUserId userId: String,
        andDeviceId deviceId: String,
        method: String,
        success: @escaping (MXKeyVerificationTransaction) -> Void,
        failure: @escaping (Swift.Error) -> Void
    ) {
        log.debug("Starting \(method) verification flow")
        
        Task {
            do {
                let transaction = try await startSasVerification(userId: userId, deviceId: deviceId)
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
        log.debug("Not implemented")
        return nil
    }
    
    func removeQRCodeTransaction(withTransactionId transactionId: String) {
        log.debug("Not implemented")
    }
    
    // MARK: - Events
    
    func handleDeviceEvents(_ events: [MXEvent]) {
        for event in events {
            guard Self.toDeviceEventTypes.contains(event.type) else {
                continue
            }
            handleDeviceEvent(event)
        }
        updatePendingVerification()
    }
    
    private func listenToRoomEvents(in session: MXSession) {
        observer = session.listenToEvents(Array(Self.dmEventTypes)) { [weak self] event, direction, customObject in
            if direction == .forwards {
                self?.handleRoomEvent(event)
            }
        }
    }
    
    private func handleDeviceEvent(_ event: MXEvent) {
        guard
            let userId = event.sender,
            let flowId = event.content["transaction_id"] as? String
        else {
            log.error("Missing userId or flowId in event")
            return
        }
        
        log.debug("->")
        
        switch event.type {
        case kMXMessageTypeKeyVerificationRequest:
            handleIncomingRequest(userId: userId, flowId: flowId, transport: .toDevice)
            
        case kMXEventTypeStringKeyVerificationStart:
            handleIncomingVerification(userId: userId, flowId: flowId, transport: .toDevice)
            
        default:
            log.failure("Event type should not be handled by key verification", context: event.type)
        }
    }
    
    private func handleRoomEvent(_ event: MXEvent) {
        log.debug("->")
        
        if event.type == kMXEventTypeStringRoomMessage && event.content?[kMXMessageTypeKey] as? String == kMXMessageTypeKeyVerificationRequest {
            handleIncomingRequest(userId: event.sender, flowId: event.eventId, transport: .directMessage)
            
        } else if event.type == kMXEventTypeStringKeyVerificationStart, let flowId = event.relatesTo.eventId {
            handleIncomingVerification(userId: event.sender, flowId: flowId, transport: .directMessage)
            
        } else if Self.dmEventTypes.contains(where: { $0.identifier == event.type }) {
            updatePendingVerification()
            
        } else if event.type != kMXEventTypeStringRoomMessage {
            log.failure("Event type should not be handled by key verification", context: event.type)
        }
    }
    
    // MARK: - Update
    
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
                activeTransactions[transaction.transactionId] = nil
            }
        }
    }
    
    // MARK: - Verification requests
    
    private func requestVerification(userId: String, roomId: String, methods: [String]) async throws -> MXKeyVerificationRequest {
        log.debug("->")
        
        let request = try await handler.requestVerification(
            userId: userId,
            roomId: roomId,
            methods: methods
        )
        return addRequest(for: request, transport: .directMessage)
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
        }
        return request
    }
    
    // MARK: - Verification transactions
    
    private func startSasVerification(userId: String, flowId: String, transport: MXKeyVerificationTransport) async throws -> MXKeyVerificationTransaction {
        log.debug("->")
        let sas = try await handler.startSasVerification(userId: userId, flowId: flowId)
        return addSasTransaction(for: sas, transport: transport)
    }
    
    private func startSasVerification(userId: String, deviceId: String) async throws -> MXKeyVerificationTransaction {
        log.debug("->")
        let sas = try await handler.startSasVerification(userId: userId, deviceId: deviceId)
        return addSasTransaction(for: sas, transport: .toDevice)
    }
    
    private func handleIncomingVerification(userId: String, flowId: String, transport: MXKeyVerificationTransport) {
        log.debug(flowId)
        
        guard activeTransactions[flowId] == nil else {
            log.debug("Transaction already known, ignoring")
            return
        }
        
        guard let verification = handler.verification(userId: userId, flowId: flowId) else {
            log.error("Verification is not known", context: [
                "flow_id": flowId
            ])
            return
        }

        log.debug("Tracking new verification transaction")
        switch verification {
        case .sasV1(let sas):
            let transaction = addSasTransaction(for: sas, transport: transport)
            transaction.accept()
        case .qrCodeV1:
            log.failure("Not implemented")
        }
    }
    
    private func addSasTransaction(
        for sas: Sas,
        transport: MXKeyVerificationTransport
    ) -> MXSASTransactionV2 {
        let transaction = MXSASTransactionV2(
            sas: sas,
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
}

extension MXKeyVerificationManagerV2: MXRecoveryServiceDelegate {
    func setUserVerification(_ isTrusted: Bool, forUser: String, success: () -> Void, failure: (Swift.Error) -> Void) {
        log.error("Not implemented")
    }
}

#endif

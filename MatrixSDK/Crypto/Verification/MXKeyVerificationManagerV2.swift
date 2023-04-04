//
//  MXKeyVerificationManagerV2.swift
//  MatrixSDK
//
//  Created by Element on 05/07/2022.
//

import Foundation
import MatrixSDKCrypto

class MXKeyVerificationManagerV2: NSObject, MXKeyVerificationManager {
    enum Error: Swift.Error {
        case requestNotSupported
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
    private let handler: MXCryptoVerifying
    
    // We need to keep track of request / transaction objects by reference
    // because various flows / screens subscribe to updates via global notifications
    // posted through them
    private var activeRequests: [String: MXKeyVerificationRequestV2]
    private var activeTransactions: [String: MXKeyVerificationTransaction]
    private let resolver: MXKeyVerificationStateResolver
    
    private let log = MXNamedLog(name: "MXKeyVerificationManagerV2")
    
    init(session: MXSession, handler: MXCryptoVerifying) {
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
        
        guard let request = request as? MXKeyVerificationRequestV2 else {
            log.failure("Incompatible type of verification request")
            failure(Error.requestNotSupported)
            return
        }
        
        Task {
            do {
                let sas = try await request.startSasVerification()
                let transaction = await addSasTransaction(for: sas, isIncoming: false)
                log.debug("Created verification transaction")
                await MainActor.run {
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
    
    @MainActor
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
        } else if let request = handler.verificationRequest(userId: event.sender, flowId: flowId), !request.isCancelled() {
            log.debug("Adding pending request")

            let result = MXKeyVerification()
            result.request = addRequest(for: request)
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

    @MainActor
    func qrCodeTransaction(withTransactionId transactionId: String) -> MXQRCodeTransaction? {
        if let transaction = activeTransactions[transactionId] as? MXQRCodeTransaction {
            return transaction
        }

        guard
            let activeRequest = activeRequests[transactionId],
            let request = handler.verificationRequest(userId: activeRequest.otherUser, flowId: activeRequest.requestId)
        else {
            log.error("There is no pending verification request")
            return nil
        }
        
        let theirMethods = request.theirSupportedMethods() ?? []
        if theirMethods.contains(MXKeyVerificationMethodQRCodeScan) {
            do {
                let qr = try activeRequest.startQrVerification()
                log.debug("Starting new QR verification")
                return addQrTransaction(for: request, qr: .code(qr), isIncoming: false)
            } catch {
                log.error("Cannot start QR verification", context: error)
                return nil
            }
        } else if theirMethods.contains(MXKeyVerificationMethodQRCodeShow) {
            /// Placehoder QR transaction generated in case we cannot start a QR verification flow
            /// (the other device cannot scan our code) but we may be able to scan theirs
            log.debug("Adding placeholder QR verification")
            return addQrTransaction(for: request, qr: .placeholder, isIncoming: false)
        }
        
        log.debug("No support for QR verification flow")
        return nil
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
            handleIncomingRequest(userId: userId, flowId: flowId)
            
        case kMXEventTypeStringKeyVerificationStart:
            handleIncomingVerification(userId: userId, flowId: flowId)
            
        default:
            log.failure("Event type should not be handled by key verification", context: event.type)
        }
    }
    
    func handleRoomEvent(_ event: MXEvent) async throws {
        guard isIncomingRoomVerificationEvent(event) else {
            return
        }
        
        if let roomId = event.roomId {
            log.debug("Recieved new verification event \(event.eventType)")
            try await handler.receiveVerificationEvent(event: event, roomId: roomId)
        }
        
        let newUserId: String?
        if event.type == kMXEventTypeStringRoomMessage && event.content?[kMXMessageTypeKey] as? String == kMXMessageTypeKeyVerificationRequest {
            await handleIncomingRequest(userId: event.sender, flowId: event.eventId)
            newUserId = event.sender
        } else if event.type == kMXEventTypeStringKeyVerificationStart, let flowId = event.relatesTo?.eventId {
            await handleIncomingVerification(userId: event.sender, flowId: flowId)
            newUserId = event.sender
        } else {
            newUserId = nil
        }

        // If we received a verification event from a new user we do not yet track
        // we need to download their keys to be able to proceed with the verification flow
        if let userId = newUserId {
            try await self.handler.downloadKeysIfNecessary(users: [userId])
        }
    }
    
    // MARK: - Verification requests
    
    @MainActor
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
    
    @MainActor
    private func requestVerification(userId: String, roomId: String, methods: [String]) async throws -> MXKeyVerificationRequest {
        log.debug("->")
        
        let request = try await handler.requestVerification(
            userId: userId,
            roomId: roomId,
            methods: methods
        )
        return addRequest(for: request)
    }
    
    @MainActor
    private func requestVerification(userId: String, deviceId: String, methods: [String]) async throws -> MXKeyVerificationRequest {
        log.debug("->")
        
        let request = try await handler.requestVerification(
            userId: userId,
            deviceId: deviceId,
            methods: methods
        )
        return addRequest(for: request)
    }
    
    @MainActor
    private func requestSelfVerification(methods: [String]) async throws -> MXKeyVerificationRequest {
        log.debug("->")

        let request = try await handler.requestSelfVerification(methods: methods)
        return addRequest(for: request)
    }
    
    @MainActor
    private func handleIncomingRequest(userId: String, flowId: String) {
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
        
        guard !req.isCancelled() else {
            log.debug("Ignoring cancelled request")
            return
        }

        log.debug("Tracking new verification request")
        
        _ = addRequest(for: req)
    }
    
    @MainActor
    private func addRequest(for request: VerificationRequestProtocol) -> MXKeyVerificationRequestV2 {
        let shouldNotify = !request.weStarted()
        let request = MXKeyVerificationRequestV2(
            request: request,
            handler: handler
        )
        activeRequests[request.requestId] = request
        if shouldNotify {
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
    
    @MainActor
    private func handleIncomingVerification(userId: String, flowId: String) {
        log.debug(flowId)
        
        guard
            let request = handler.verificationRequest(userId: userId, flowId: flowId),
            let verification = handler.verification(userId: userId, flowId: flowId)
        else {
            log.error("Verification is not known", context: [
                "flow_id": flowId
            ])
            return
        }
        
        switch verification {
        case .sas(let sas):
            log.debug("Tracking new SAS verification transaction")
            let transaction = addSasTransaction(for: sas, isIncoming: true)
            if activeRequests[transaction.transactionId] != nil {
                log.debug("Auto-accepting transaction that matches a pending request")
                transaction.accept()
            }
        case .qrCode(let qrCode):
            if activeTransactions[flowId] is MXQRCodeTransaction {
                // This flow may happen if we have previously started a QR verification, but so has the other side,
                // and we scanned their code which now takes over the verification flow
                log.debug("Updating existing QR verification transaction")
            } else {
                log.debug("Tracking new QR verification transaction")
                _ = addQrTransaction(for: request, qr: .code(qrCode), isIncoming: true)
            }
        }
    }
    
    @MainActor
    private func addSasTransaction(for sas: SasProtocol, isIncoming: Bool) -> MXSASTransactionV2 {
        let transaction = MXSASTransactionV2(sas: sas, isIncoming: isIncoming, handler: handler)
        activeTransactions[transaction.transactionId] = transaction
        return transaction
    }
    
    @MainActor
    private func addQrTransaction(for request: VerificationRequestProtocol, qr: MXQRCodeTransactionV2.QrKind, isIncoming: Bool) -> MXQRCodeTransactionV2 {
        let transaction = MXQRCodeTransactionV2(request: request, qr: qr, isIncoming: isIncoming, handler: handler)
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
    
    private func isIncomingRoomVerificationEvent(_ event: MXEvent) -> Bool {
        // Only consider events not coming from our own user, because verification events
        // for the same user are sent as encrypted to-device messages
        guard event.sender != session?.myUserId else {
            return false
        }
        
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

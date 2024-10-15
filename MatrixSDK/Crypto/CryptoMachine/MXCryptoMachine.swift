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

typealias GetRoomAction = (String) -> MXRoom?

/// Wrapper around Rust-based `OlmMachine`, providing a more convenient API.
///
/// Two main responsibilities of the `MXCryptoMachine` are:
/// - mapping to and from raw strings passed into the Rust machine
/// - performing network requests and marking them as completed on behalf of the Rust machine
class MXCryptoMachine {
    actor RoomQueues {
        private var queues = [String: MXTaskQueue]()
        
        func getQueue(for roomId: String) -> MXTaskQueue {
            let queue = queues[roomId] ?? MXTaskQueue()
            queues[roomId] = queue
            return queue
        }
    }
    
    private static let kdfRounds: Int32 = 500_000
    // Error type will be moved to rust sdk
    private static let MismatchedAccountError = "the account in the store doesn't match the account in the constructor"
    
    enum Error: Swift.Error {
        case invalidEvent
        case cannotSerialize
        case missingRoom
        case missingVerificationContent
        case missingVerificationRequest
        case missingVerification
        case cannotExportKeys
        case cannotImportKeys
    }
    
    private let machine: OlmMachine
    private let requests: MXCryptoRequests
    private let getRoomAction: GetRoomAction
    
    private let sessionsQueue = MXTaskQueue()
    private let syncQueue = MXTaskQueue()
    private var roomQueues = RoomQueues()
    
    // Temporary properties to help with the performance of backup keys checks
    // until the performance is improved in the rust-sdk
    private var cachedRoomKeyCounts: RoomKeyCounts?
    private var isComputingRoomKeyCounts = false
    private let processingQueue = DispatchQueue(label: "org.matrix.sdk.MXCryptoMachine.processingQueue")
    
    private let log = MXNamedLog(name: "MXCryptoMachine")

    init(
        userId: String,
        deviceId: String,
        restClient: MXRestClient,
        getRoomAction: @escaping GetRoomAction
    ) throws {
        MXCryptoSDKLogger.shared.log(logLine: "Starting logs")
        
        self.machine = try Self.createMachine(userId: userId, deviceId: deviceId, log: log)
        self.requests = MXCryptoRequests(restClient: restClient)
        self.getRoomAction = getRoomAction
        
        let details = """
        Initialized the crypto machine for \(userId)
          - device id  : \(deviceId)
          - ed25519    : \(deviceEd25519Key ?? "")
          - curve25519 : \(deviceCurve25519Key ?? "")
        """
        log.debug(details)
    }
    
    func uploadKeysIfNecessary() async throws {
        log.debug("Checking for keys to upload")
        
        var keysUploadRequest: Request?
        for request in try machine.outgoingRequests() {
            guard case .keysUpload = request else {
                continue
            }
            keysUploadRequest = request
            break
        }
        
        guard let request = keysUploadRequest else {
            log.debug("There are no keys to upload")
            return
        }
        
        log.debug("We have some keys to upload")
        try await handleRequest(request)
        log.debug("Keys successfully uploaded")
    }
    
    func deleteAllData() throws {
        let url = try MXCryptoMachineStore.storeURL(for: userId)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
    
    // MARK: - Private
    
    private static func createMachine(userId: String, deviceId: String, log: MXNamedLog) throws -> OlmMachine {
        let url = try MXCryptoMachineStore.createStoreURLIfNecessary(for: userId)
        let passphrase = try MXCryptoMachineStore.storePassphrase()
        
        log.debug("Opening crypto store at \(url.path)/matrix-sdk-crypto.sqlite3") // Hardcoding full path to db for debugging purposes
        
        do {
            return try OlmMachine(
                userId: userId,
                deviceId: deviceId,
                path: url.path,
                passphrase: passphrase
            )
        } catch {
            // If we cannot open machine due to a mismatched account, delete previous data and try again
            if case CryptoStoreError.CryptoStore(let message) = error,
               message.contains(Self.MismatchedAccountError) {
                log.error("Credentials of the account do not match, deleting previous data", context: [
                    "error": message
                ])
                try FileManager.default.removeItem(at: url)
                return try OlmMachine(
                    userId: userId,
                    deviceId: deviceId,
                    path: url.path,
                    passphrase: passphrase
                )

            // Otherwise re-throw the error
            } else {
                throw error
            }
        }
    }
}

extension MXCryptoMachine: MXCryptoIdentity {
    var userId: String {
        return machine.userId()
    }
    
    var deviceId: String {
        return machine.deviceId()
    }
    
    var deviceCurve25519Key: String? {
        guard let key = machine.identityKeys()[kMXKeyCurve25519Type] else {
            log.failure("Cannot get device curve25519 key")
            return nil
        }
        return key
    }
    
    var deviceEd25519Key: String? {
        guard let key = machine.identityKeys()[kMXKeyEd25519Type] else {
            log.failure("Cannot get device ed25519 key")
            return nil
        }
        return key
    }
}

extension MXCryptoMachine: MXCryptoSyncing {
    
    @MainActor
    func handleSyncResponse(
        toDevice: MXToDeviceSyncResponse?,
        deviceLists: MXDeviceListResponse?,
        deviceOneTimeKeysCounts: [String: NSNumber],
        unusedFallbackKeys: [String]?,
        nextBatchToken: String
    ) throws -> MXToDeviceSyncResponse {
        let events = toDevice?.jsonString() ?? "[]"
        let deviceChanges = DeviceLists(
            changed: deviceLists?.changed ?? [],
            left: deviceLists?.left ?? []
        )
        let keyCounts = deviceOneTimeKeysCounts.compactMapValues { $0.int32Value }
        
        let result = try machine.receiveSyncChanges(
            events: events,
            deviceChanges: deviceChanges,
            keyCounts: keyCounts,
            unusedFallbackKeys: unusedFallbackKeys,
            nextBatchToken: nextBatchToken
        )
        
        var deserialisedToDeviceEvents = [Any]()
        for toDeviceEvent in result.toDeviceEvents {
            guard let deserialisedToDeviceEvent = MXTools.deserialiseJSONString(toDeviceEvent) else {
                log.failure("Failed deserialising to device event", context: [
                    "result": result
                ])
                return MXToDeviceSyncResponse()
            }
            
            deserialisedToDeviceEvents.append(deserialisedToDeviceEvent)
        }
        
        guard let toDeviceSyncResponse = MXToDeviceSyncResponse(fromJSON: ["events": deserialisedToDeviceEvents]) else {
            log.failure("Result cannot be serialized", context: [
                "result": result
            ])
            return MXToDeviceSyncResponse()
        }
        
        return toDeviceSyncResponse
    }
    
    func downloadKeysIfNecessary(users: [String]) async throws {
        log.debug("Checking if keys need to be downloaded for \(users.count) user(s)")
        
        try machine.updateTrackedUsers(users: users)

        // Out-of-sync check if there is a pending outgoing request for some of these users
        // (note that if a request is already in-flight, keys query scheduler will deduplicate them)
        for request in try machine.outgoingRequests() {
            if case .keysQuery(_, let requestUsers) = request {
                let usersInCommon = Set(requestUsers).intersection(users)
                if !usersInCommon.isEmpty {
                    try await handleRequest(request)
                    return
                }
            }
        }
    }
    
    @available(*, deprecated, message: "The application should not manually force reload keys, use `downloadKeysIfNecessary` instead")
    func reloadKeys(users: [String]) async throws {
        try machine.updateTrackedUsers(users: users)
        try await handleRequest(
            .keysQuery(requestId: UUID().uuidString, users: users)
        )
    }
    
    func processOutgoingRequests() async throws {
        try await syncQueue.sync { [weak self] in
            try await self?.handleOutgoingRequests()
        }
    }
    
    // MARK: - Private
    
    private func handleRequest(_ request: Request) async throws {
        log.debug("Handling `\(request.type)` request")
        
        switch request {
        case .toDevice(let requestId, let eventType, let body):
            try await requests.sendToDevice(
                request: .init(eventType: eventType, body: body, addMessageId: true)
            )
            try markRequestAsSent(requestId: requestId, requestType: .toDevice)

        case .keysUpload(let requestId, let body):
            let response = try await requests.uploadKeys(
                request: .init(body: body, deviceId: machine.deviceId())
            )
            try markRequestAsSent(requestId: requestId, requestType: .keysUpload, response: response.jsonString())
            
        case .keysQuery(let requestId, let users):
            let response = try await requests.queryKeys(users: users)
            try markRequestAsSent(requestId: requestId, requestType: .keysQuery, response: response.jsonString())
            
        case .keysClaim(let requestId, let oneTimeKeys):
            log.debug("Claiming keys \(oneTimeKeys)")
            
            let response = try await requests.claimKeys(
                request: .init(oneTimeKeys: oneTimeKeys)
            )
            
            let dictionary = response.jsonDictionary() as? [String: Any] ?? [:]
            log.debug("Keys claimed\n\(dictionary)")
            try markRequestAsSent(requestId: requestId, requestType: .keysClaim, response: response.jsonString())

        case .keysBackup(let requestId, let version, let rooms):
            let response = try await requests.backupKeys(
                request: .init(version: version, rooms: rooms)
            )
            try markRequestAsSent(requestId: requestId, requestType: .keysBackup, response: MXTools.serialiseJSONObject(response))
            
        case .roomMessage(let requestId, let roomId, let eventType, let content):
            guard let eventID = try await sendRoomMessage(roomId: roomId, eventType: eventType, content: content) else {
                throw Error.invalidEvent
            }
            let event = [
                "event_id": eventID
            ]
            try markRequestAsSent(requestId: requestId, requestType: .roomMessage, response: MXTools.serialiseJSONObject(event))
            
        case .signatureUpload(let requestId, let body):
            try await requests.uploadSignatures(
                request: .init(body: body)
            )
            let event = [
                "failures": [:]
            ]
            try markRequestAsSent(requestId: requestId, requestType: .signatureUpload, response: MXTools.serialiseJSONObject(event))
        }
    }
    
    private func markRequestAsSent(requestId: String, requestType: RequestType, response: String? = nil) throws {
        try self.machine.markRequestAsSent(requestId: requestId, requestType: requestType, responseBody: response ?? "")
    }
    
    private func handleOutgoingRequests() async throws {
        let requests = try machine.outgoingRequests()
        
        try await withThrowingTaskGroup(of: Void.self) { [weak self] group in
            guard let self = self else { return }
            for request in requests {
                group.addTask {
                    try await self.handleRequest(request)
                }
            }
            
            try await group.waitForAll()
        }
    }
    
    private func sendRoomMessage(roomId: String, eventType: String, content: String) async throws -> String? {
        guard let room = getRoomAction(roomId) else {
            throw Error.missingRoom
        }
        return try await requests.roomMessage(
            request: .init(
                room: room,
                eventType: eventType,
                content: content
            )
        )
    }
}

extension MXCryptoMachine: MXCryptoDevicesSource {
    func devices(userId: String) -> [Device] {
        do {
            return try machine.getUserDevices(userId: userId, timeout: 0)
        } catch {
            log.error("Cannot fetch devices", context: error)
            return []
        }
    }
    
    func device(userId: String, deviceId: String) -> Device? {
        do {
            return try machine.getDevice(userId: userId, deviceId: deviceId, timeout: 0)
        } catch {
            log.error("Cannot fetch device", context: error)
            return nil
        }
    }
    
    func dehydratedDevices() -> DehydratedDevicesProtocol {
        machine.dehydratedDevices()
    }
}

extension MXCryptoMachine: MXCryptoUserIdentitySource {
    func isUserVerified(userId: String) -> Bool {
        do {
            return try machine.isIdentityVerified(userId: userId)
        } catch {
            log.error("Failed checking user verification status", context: error)
            return false
        }
    }
    
    func userIdentity(userId: String) -> UserIdentity? {
        do {
            return try machine.getIdentity(userId: userId, timeout: 0)
        } catch {
            log.error("Failed fetching user identity")
            return nil
        }
    }
    
    func verifyUser(userId: String) async throws {
        let request = try machine.verifyIdentity(userId: userId)
        try await requests.uploadSignatures(request: request)
    }
    
    func verifyDevice(userId: String, deviceId: String) async throws {
        let request = try machine.verifyDevice(userId: userId, deviceId: deviceId)
        try await requests.uploadSignatures(request: request)
    }
    
    func setLocalTrust(userId: String, deviceId: String, trust: LocalTrust) throws {
        try machine.setLocalTrust(userId: userId, deviceId: deviceId, trustState: trust)
    }
}

extension MXCryptoMachine: MXCryptoRoomEventEncrypting {
    var onlyAllowTrustedDevices: Bool {
        get {
            do {
                return try machine.getOnlyAllowTrustedDevices()
            } catch {
                log.error("Failed getting value", context: error)
                return false
            }
        }
        set {
            do {
                try machine.setOnlyAllowTrustedDevices(onlyAllowTrustedDevices: newValue)
            } catch {
                log.error("Failed setting value", context: error)
            }
        }
    }
    
    func isUserTracked(userId: String) -> Bool {
        do {
            return try machine.isUserTracked(userId: userId)
        } catch {
            log.error("Failed getting tracked status", context: error)
            return false
        }
    }
    
    func updateTrackedUsers(_ users: [String]) {
        do {
            try machine.updateTrackedUsers(users: users)
        } catch {
            log.error("Failed updating tracked users", context: error)
        }
    }
    
    func roomSettings(roomId: String) -> RoomSettings? {
        do {
            return try machine.getRoomSettings(roomId: roomId)
        } catch {
            log.error("Failed getting room settings", context: error)
            return nil
        }
    }
    
    func setRoomAlgorithm(roomId: String, algorithm: EventEncryptionAlgorithm) throws {
        try machine.setRoomAlgorithm(roomId: roomId, algorithm: algorithm)
    }
    
    func setOnlyAllowTrustedDevices(for roomId: String, onlyAllowTrustedDevices: Bool) throws {
        try machine.setRoomOnlyAllowTrustedDevices(roomId: roomId, onlyAllowTrustedDevices: onlyAllowTrustedDevices)
    }
    
    func shareRoomKeysIfNecessary(
        roomId: String,
        users: [String],
        settings: EncryptionSettings
    ) async throws {
        log.debug("Checking room keys in room \(roomId)")
        
        try await sessionsQueue.sync { [weak self] in
            try await self?.getMissingSessions(users: users)
        }
        
        let roomQueue = await roomQueues.getQueue(for: roomId)
        
        try await roomQueue.sync { [weak self] in
            try await self?.shareRoomKey(roomId: roomId, users: users, settings: settings)
        }
    }
    
    func encryptRoomEvent(
        content: [AnyHashable : Any],
        roomId: String,
        eventType: String
    ) throws -> [String : Any] {
        guard let content = MXTools.serialiseJSONObject(content) else {
            throw Error.cannotSerialize
        }
        
        let event = try machine.encrypt(roomId: roomId, eventType: eventType as String, content: content)
        return MXTools.deserialiseJSONString(event) as? [String: Any] ?? [:]
    }
    
    func discardRoomKey(roomId: String) {
        do {
            try machine.discardRoomKey(roomId: roomId)
        } catch {
            log.error("Cannot discard room key", context: error)
        }
    }
    
    // MARK: - Private
    
    private func getMissingSessions(users: [String]) async throws {
        log.debug("Checking missing olm sessions for \(users.count) user(s): \(users)")
        
        guard
            let request = try machine.getMissingSessions(users: users),
            case .keysClaim = request
        else {
            log.debug("No olm sessions are missing")
            return
        }
        
        log.debug("Claiming new keys")
        try await handleRequest(request)
    }
    
    private func shareRoomKey(roomId: String, users: [String], settings: EncryptionSettings) async throws {
        log.debug("Checking unshared room keys")
        
        let requests = try machine.shareRoomKey(roomId: roomId, users: users, settings: settings)
        guard !requests.isEmpty else {
            log.debug("There are no new keys to share")
            return
        }
        
        log.debug("Created \(requests.count) key share requests")
        try await withThrowingTaskGroup(of: Void.self) { [weak self] group in
            guard let self = self else { return }
            
            for request in requests {
                guard case .toDevice = request else {
                    continue
                }
                
                group.addTask {
                    try await self.handleRequest(request)
                }
            }
            
            try await group.waitForAll()
        }
        
        log.debug("All room keys have been shared")
    }
}

extension MXCryptoMachine: MXCryptoRoomEventDecrypting {
    func decryptRoomEvent(_ event: MXEvent) throws -> DecryptedEvent {
        guard let roomId = event.roomId, let eventString = event.jsonString() else {
            log.failure("Invalid event")
            throw Error.invalidEvent
        }
        return try machine.decryptRoomEvent(
            event: eventString,
            roomId: roomId,
            // Handling verification events automatically during event decryption is now a deprecated behavior,
            // all verification events are handled manually via `receiveVerificationEvent`
            handleVerificationEvents: false,
            // The app does not use strict shields by default, in the future this will become configurable
            // per room.
            strictShields: false
        )
    }
    
    func requestRoomKey(event: MXEvent) async throws {
        guard let roomId = event.roomId, let eventString = event.jsonString() else {
            throw Error.invalidEvent
        }
        
        log.debug("->")
        let result = try machine.requestRoomKey(event: eventString, roomId: roomId)
        if let cancellation = result.cancellation {
            try await handleRequest(cancellation)
        }
        try await handleRequest(result.keyRequest)
    }
}

extension MXCryptoMachine: MXCryptoCrossSigning {
    func refreshCrossSigningStatus() async throws {
        try await reloadKeys(users: [userId])
    }
    
    func crossSigningStatus() -> CrossSigningStatus {
        return machine.crossSigningStatus()
    }
    
    func bootstrapCrossSigning(authParams: [AnyHashable: Any]) async throws {
        let result = try machine.bootstrapCrossSigning()
        // If this is called before the device keys have been uploaded there will be a
        // request to upload them, do that first.
        if let optionalKeyRequest = result.uploadKeysRequest {
            try await handleRequest(optionalKeyRequest)
        }
        let _ = try await [
            requests.uploadSigningKeys(request: result.uploadSigningKeysRequest, authParams: authParams),
            requests.uploadSignatures(request: result.uploadSignatureRequest)
        ]
    }
    
    func exportCrossSigningKeys() -> CrossSigningKeyExport? {
        do {
            return try machine.exportCrossSigningKeys()
        } catch {
            log.error("Failed exporting cross signing keys", context: error)
            return nil
        }
    }
    
    func importCrossSigningKeys(export: CrossSigningKeyExport) throws {
        do {
            try machine.importCrossSigningKeys(export: export)
        } catch {
            log.error("Failed importing cross signing keys", context: error)
            throw error
        }
    }
    
    func queryMissingSecretsFromOtherSessions() async throws {
        let isMissingSecrets = try machine.queryMissingSecretsFromOtherSessions()
        
        if (isMissingSecrets) {
            // Out-of-sync check if there are any secret request to send out as a result of
            // the missing secret request
            for request in try machine.outgoingRequests() {
                if case .toDevice(_, let eventType, _) = request {
                    if (eventType == kMXEventTypeStringSecretRequest) {
                        try await handleRequest(request)
                    }
                }
            }
        }
    }
    
}

extension MXCryptoMachine: MXCryptoVerifying {
    func receiveVerificationEvent(event: MXEvent, roomId: String) async throws {
        let event = try verificationEventString(for: event)
        try machine.receiveVerificationEvent(event: event, roomId: roomId)
        
        // Out-of-sync check if there are any verification events to sent out as a result of
        // the event just received
        for request in try machine.outgoingRequests() {
            if case .roomMessage = request {
                try await handleRequest(request)
                return
            }
        }
    }
    
    func requestSelfVerification(methods: [String]) async throws -> VerificationRequestProtocol {
        guard let result = try machine.requestSelfVerification(methods: methods) else {
            throw Error.missingVerification
        }
        try await handleOutgoingVerificationRequest(result.request)
        return result.verification
    }
    
    func requestVerification(userId: String, roomId: String, methods: [String]) async throws -> VerificationRequestProtocol {
        guard let content = try machine.verificationRequestContent(userId: userId, methods: methods) else {
            throw Error.missingVerificationContent
        }
        
        let eventId = try await sendRoomMessage(
            roomId: roomId,
            eventType: kMXEventTypeStringRoomMessage,
            content: content
        )
        guard let eventId = eventId else {
            throw Error.invalidEvent
        }
        
        let request = try machine.requestVerification(
            userId: userId,
            roomId: roomId,
            eventId: eventId,
            methods: methods
        )
        
        guard let request = request else {
            throw Error.missingVerificationRequest
        }
        return request
    }
    
    func requestVerification(userId: String, deviceId: String, methods: [String]) async throws -> VerificationRequestProtocol {
        guard let result = try machine.requestVerificationWithDevice(userId: userId, deviceId: deviceId, methods: methods) else {
            throw Error.missingVerificationRequest
        }
        try await handleOutgoingVerificationRequest(result.request)
        return result.verification
    }
    
    func verificationRequests(userId: String) -> [VerificationRequestProtocol] {
        return machine.getVerificationRequests(userId: userId)
    }
    
    func verificationRequest(userId: String, flowId: String) -> VerificationRequestProtocol? {
        return machine.getVerificationRequest(userId: userId, flowId: flowId)
    }
    
    func verification(userId: String, flowId: String) -> MXVerification? {
        guard let verification = machine.getVerification(userId: userId, flowId: flowId) else {
            return nil
        }
        
        if let sas = verification.asSas() {
            return .sas(sas)
        } else if let qrCode = verification.asQr() {
            return .qrCode(qrCode)
        } else {
            log.failure("Invalid state of verification")
            return nil
        }
    }
    
    func handleOutgoingVerificationRequest(_ request: OutgoingVerificationRequest) async throws {
        switch request {
        case .toDevice(_, let eventType, let body):
            try await requests.sendToDevice(
                request: .init(
                    eventType: eventType,
                    body: body,
                    // Should not add anything for verification events as it would break their signatures
                    addMessageId: false
                )
            )
        case .inRoom(_, let roomId, let eventType, let content):
            let _ = try await sendRoomMessage(
                roomId: roomId,
                eventType: eventType,
                content: content
            )
        }
        
        try await processOutgoingRequests()
    }
    
    func handleVerificationConfirmation(_ result: ConfirmVerificationResult) async throws {
        if let request = result.signatureRequest {
            try await requests.uploadSignatures(request: request)
        }
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for request in result.requests {
                group.addTask {
                    try await self.handleOutgoingVerificationRequest(request)
                }
            }
            
            try await group.waitForAll()
        }
    }
    
    private func verificationEventString(for event: MXEvent) throws -> String {
        guard var dictionary = event.jsonDictionary() else {
            throw Error.invalidEvent
        }
        
        // If this is a decrypted event, we need to swap out `type` and `content` properties
        // as this is what the crypto machine expects decrypted events to look like
        if let clear = event.clear {
            dictionary["type"] = clear.type
            dictionary["content"] = clear.content
        }

        guard let string = MXTools.serialiseJSONObject(dictionary) else {
            throw Error.invalidEvent
        }
        
        return string
    }
}

extension MXCryptoMachine: MXCryptoBackup {
    var isBackupEnabled: Bool {
        return machine.backupEnabled()
    }
    
    var backupKeys: BackupKeys? {
        do {
            return try machine.getBackupKeys()
        } catch {
            log.error("Failed fetching backup keys", context: error)
            return nil
        }
    }
    
    var roomKeyCounts: RoomKeyCounts? {
        // Checking the number of backed-up keys is currently very compute-heavy
        // and blocks the main thread for large accounts. A light-weight `hasKeysToBackup`
        // method will be added into rust-sdk and for the time-being we return cached counts
        // on the main thread and compute new value on separate queue
        if !isComputingRoomKeyCounts {
            processingQueue.async { [weak self] in
                self?.updateRoomKeyCounts()
            }
        }
        return cachedRoomKeyCounts
    }
    
    func enableBackup(key: MegolmV1BackupKey, version: String) throws {
        try machine.enableBackupV1(key: key, version: version)
    }
    
    func disableBackup() {
        do {
            try machine.disableBackup()
        } catch {
            log.error("Failed disabling backup", context: error)
        }
    }
    
    func saveRecoveryKey(key: BackupRecoveryKey, version: String?) throws {
        try machine.saveRecoveryKey(key: key, version: version)
    }
    
    func verifyBackup(version: MXKeyBackupVersion) -> Bool {
        guard let string = version.jsonString() else {
            log.error("Cannot serialize backup version")
            return false
        }
        
        do {
            let verification = try machine.verifyBackup(backupInfo: string)
            return verification.trusted
        } catch {
            log.error("Failed verifying backup", context: error)
            return false
        }
    }
    
    func sign(object: [AnyHashable: Any]) throws -> [String: [String: String]] {
        guard let message = MXCryptoTools.canonicalJSONString(forJSON: object) else {
            throw Error.cannotSerialize
        }
        return try machine.sign(message: message)
    }
    
    func backupRoomKeys() async throws {
        guard
            let request = try machine.backupRoomKeys(),
            case .keysBackup = request
        else {
            return
        }
        try await handleRequest(request)
    }
    
    func importDecryptedKeys(roomKeys: [MXMegolmSessionData], progressListener: ProgressListener) throws -> KeysImportResult {
        let jsonKeys = roomKeys.compactMap { $0.jsonDictionary() }
        guard let json = MXTools.serialiseJSONObject(jsonKeys) else {
            throw Error.cannotSerialize
        }
        return try machine.importDecryptedRoomKeys(keys: json, progressListener: progressListener)
    }
    
    func exportRoomKeys(passphrase: String) throws -> Data {
        let string = try machine.exportRoomKeys(passphrase: passphrase, rounds: Self.kdfRounds)
        guard let data = string.data(using: .utf8) else {
            throw Error.cannotExportKeys
        }
        return data
    }
    
    func importRoomKeys(_ data: Data, passphrase: String, progressListener: ProgressListener) throws -> KeysImportResult {
        guard let string = String(data: data, encoding: .utf8) else {
            throw Error.cannotImportKeys
        }
        return try machine.importRoomKeys(keys: string, passphrase: passphrase, progressListener: progressListener)
    }
    
    // MARK: - Private
    
    private func updateRoomKeyCounts() {
        // Checking condition again for safety as we are on another thread
        guard !isComputingRoomKeyCounts else {
            return
        }
        
        isComputingRoomKeyCounts = true
        do {
            cachedRoomKeyCounts = try machine.roomKeyCounts()
        } catch {
            log.error("Cannot get room key counts", context: error)
            cachedRoomKeyCounts = nil
        }
        isComputingRoomKeyCounts = false
    }
}

extension Request {
    var type: RequestType {
        switch self {
        case .toDevice:
            return .toDevice
        case .keysUpload:
            return .keysUpload
        case .keysQuery:
            return .keysQuery
        case .keysClaim:
            return .keysClaim
        case .keysBackup:
            return .keysBackup
        case .roomMessage:
            return .roomMessage
        case .signatureUpload:
            return .signatureUpload
        }
    }
}

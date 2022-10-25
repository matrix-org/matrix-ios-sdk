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
public extension MXLegacyCrypto {
    /// Create a Rust-based work-in-progress implementation of `MXCrypto`
    ///
    /// The experimental crypto module is created only if:
    /// - using DEBUG build
    /// - enabling `enableCryptoV2` feature flag
    @objc static func createCryptoV2IfAvailable(session: MXSession!) -> MXCrypto? {
        let log = MXNamedLog(name: "MXCryptoV2")
        
        guard MXSDKOptions.sharedInstance().enableCryptoV2 else {
            return nil
        }
        
        guard
            let session = session,
            let restClient = session.matrixRestClient,
            let userId = restClient.credentials?.userId,
            let deviceId = restClient.credentials?.deviceId
        else {
            log.failure("Cannot create crypto V2, missing properties")
            return nil
        }
        
        do {
            return try MXCryptoV2(userId: userId, deviceId: deviceId, session: session, restClient: restClient)
        } catch {
            log.failure("Error creating crypto V2", context: error)
            return nil
        }
    }
}
#endif

#if DEBUG

import MatrixSDKCrypto

/// A work-in-progress implementation of `MXCrypto` which uses [matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk/tree/main/crates/matrix-sdk-crypto)
/// under the hood.
private class MXCryptoV2: NSObject, MXCrypto, MXRecoveryServiceDelegate {
    enum Error: Swift.Error {
        case missingRoom
    }
    
    public var deviceCurve25519Key: String! {
        return machine.deviceCurve25519Key
    }
    
    public var deviceEd25519Key: String! {
        return machine.deviceEd25519Key
    }
    
    public var keyVerificationManager: MXKeyVerificationManager! {
        return keyVerification
    }
    
    private let cryptoQueue: DispatchQueue
    
    private weak var session: MXSession?
    
    private let machine: MXCryptoMachine
    private let deviceInfoSource: MXDeviceInfoSource
    private let trustLevelSource: MXTrustLevelSource
    let crossSigning: MXCrossSigning
    private let keyVerification: MXKeyVerificationManagerV2
    private let backupEngine: MXCryptoKeyBackupEngine
    let backup: MXKeyBackup
    private(set) var recoveryService: MXRecoveryService!
    
    private var undecryptableEvents = [String: MXEvent]()
    
    private let log = MXNamedLog(name: "MXCryptoV2")
    
    public init(userId: String, deviceId: String, session: MXSession, restClient: MXRestClient) throws {
        self.cryptoQueue = DispatchQueue(label: "MXCryptoV2-\(userId)")
        self.session = session
        
        machine = try MXCryptoMachine(
            userId: userId,
            deviceId: deviceId,
            restClient: restClient,
            getRoomAction: { [weak session] roomId in
                session?.room(withRoomId: roomId)
            }
        )
        
        deviceInfoSource = MXDeviceInfoSource(source: machine)
        trustLevelSource = MXTrustLevelSource(
            userIdentitySource: machine,
            devicesSource: machine
        )
        
        crossSigning = MXCrossSigningV2(
            crossSigning: machine,
            restClient: restClient
        )
        
        keyVerification = MXKeyVerificationManagerV2(
            session: session,
            handler: machine
        )
        
        backupEngine = MXCryptoKeyBackupEngine(backup: machine)
        backup = MXKeyBackup(
            engine: backupEngine,
            restClient: restClient,
            secretShareManager: MXSecretShareManager(),
            queue: cryptoQueue
        )
        
        super.init()
        
        recoveryService = MXRecoveryService(
            dependencies: .init(
                credentials: restClient.credentials,
                backup: backup,
                secretStorage: MXSecretStorage(
                    matrixSession: session,
                    processingQueue: cryptoQueue
                ),
                secretStore: MXCryptoSecretStoreV2(
                    backup: backup,
                    backupEngine: backupEngine,
                    crossSigning: machine
                ),
                crossSigning: crossSigning,
                cryptoQueue: cryptoQueue
            ),
            delegate: self
        )
    }
    
    // MARK: - Start / close
    
    public func start(
        _ onComplete: (() -> Void)!,
        failure: ((Swift.Error?) -> Void)!
    ) {
        onComplete?()
        machine.onInitialKeysUpload { [weak self] in
            guard let self = self else { return }
            
            self.crossSigning.refreshState(success: nil)
            self.backup.checkAndStart()
        }
    }
    
    public func close(_ deleteStore: Bool) {
        undecryptableEvents = [:]
        if deleteStore {
            do {
                try machine.deleteAllData()
            } catch {
                log.failure("Cannot delete crypto store", context: error)
            }
        }
    }
    
    // MARK: - Encrypt / Decrypt
    
    public func encryptEventContent(
        _ eventContent: [AnyHashable : Any]!,
        withType eventType: String!,
        in room: MXRoom!,
        success: (([AnyHashable : Any]?, String?) -> Void)!,
        failure: ((Swift.Error?) -> Void)!
    ) -> MXHTTPOperation! {
        let startDate = Date()
        
        guard let content = eventContent, let eventType = eventType, let roomId = room?.roomId else {
            log.failure("Missing data to encrypt")
            return nil
        }
        
        guard isRoomEncrypted(roomId) else {
            log.failure("Attempting to encrypt event in room without encryption")
            return nil
        }
        
        log.debug("Encrypting content of type `\(eventType)`")
        
        Task {
            do {
                let users = try await getRoomUserIds(for: room)
                let result = try await machine.encryptRoomEvent(
                    content: content,
                    roomId: roomId,
                    eventType: eventType,
                    users: users
                )
                
                let duration = Date().timeIntervalSince(startDate) * 1000
                log.debug("Encrypted in \(duration) ms")
                await MainActor.run {
                    success?(result, kMXEventTypeStringRoomEncrypted)
                }
            } catch {
                log.error("Error encrypting content", context: error)
                await MainActor.run {
                    failure?(error)
                }
            }
        }
        return MXHTTPOperation()
    }
    
    public func decryptEvents(
        _ events: [MXEvent]!,
        inTimeline timeline: String!,
        onComplete: (([MXEventDecryptionResult]?) -> Void)!
    ) {
        let results = events?.map(decrypt(event:))
        onComplete?(results)
    }
    
    public func ensureEncryption(
        inRoom roomId: String!,
        success: (() -> Void)!,
        failure: ((Swift.Error?) -> Void)!
    ) -> MXHTTPOperation! {
        guard let roomId = roomId, let room = session?.room(withRoomId: roomId) else {
            log.failure("Missing room")
            return nil
        }
        
        Task {
            do {
                let users = try await getRoomUserIds(for: room)
                try await machine.shareRoomKeysIfNecessary(roomId: roomId, users: users)
                await MainActor.run {
                    success?()
                }
            } catch {
                log.error("Error ensuring encryption", context: error)
                await MainActor.run {
                    failure?(error)
                }
            }
        }
        
        return MXHTTPOperation()
    }
    
    public func discardOutboundGroupSessionForRoom(withRoomId roomId: String!, onComplete: (() -> Void)!) {
        guard let roomId = roomId else {
            log.failure("Missing room id")
            return
        }
        
        log.debug("Discarding room key")
        machine.discardRoomKey(roomId: roomId)
        onComplete?()
    }
    
    private func decrypt(event: MXEvent) -> MXEventDecryptionResult {
        guard event.isEncrypted && event.content?["algorithm"] as? String == kMXCryptoMegolmAlgorithm else {
            log.debug("Ignoring non-room event")
            return MXEventDecryptionResult()
        }
        
        let result = machine.decryptRoomEvent(event)
        if result.clearEvent == nil {
            undecryptableEvents[event.eventId] = event
        }
        return result
    }
    
    private func retryUndecryptableEvents() {
        for (eventId, event) in undecryptableEvents {
            let result = decrypt(event: event)
            if result.clearEvent != nil {
                event.setClearData(result)
                undecryptableEvents[eventId] = nil
            }
        }
    }
    
    // MARK: - Sync
    
    public func handle(_ syncResponse: MXSyncResponse!) {
        guard let syncResponse = syncResponse else {
            log.failure("Missing sync response")
            return
        }
        
        do {
            let toDevice = try machine.handleSyncResponse(
                toDevice: syncResponse.toDevice,
                deviceLists: syncResponse.deviceLists,
                deviceOneTimeKeysCounts: syncResponse.deviceOneTimeKeysCount ?? [:],
                unusedFallbackKeys: syncResponse.unusedFallbackKeys
            )
            keyVerification.handleDeviceEvents(toDevice.events)
            backup.maybeSend()
        } catch {
            log.error("Cannot handle sync", context: error)
        }
    }
    
    public func handleDeviceListsChanges(_ deviceLists: MXDeviceListResponse!) {
        // Not implemented, handled automatically by CryptoMachine
    }
    
    public func handleDeviceOneTimeKeysCount(_ deviceOneTimeKeysCount: [String : NSNumber]!) {
        // Not implemented, handled automatically by CryptoMachine
    }
    
    public func handleDeviceUnusedFallbackKeys(_ deviceUnusedFallbackKeys: [String]!) {
        // Not implemented, handled automatically by CryptoMachine
    }
    
    public func handleRoomKeyEvent(_ event: MXEvent!, onComplete: (() -> Void)!) {
        // Not implemented, handled automatically by CryptoMachine
    }
    
    public func onSyncCompleted(_ oldSyncToken: String!, nextSyncToken: String!, catchingUp: Bool) {
        Task {
            do {
                try await machine.completeSync()
            } catch {
                log.failure("Error processing outgoing requests", context: error)
            }
        }
    }
    
    // MARK: - Trust level
    
    public func trustLevel(forUser userId: String!) -> MXUserTrustLevel! {
        guard let userId = userId else {
            log.failure("Missing user id")
            return nil
        }
        return trustLevelSource.userTrustLevel(userId: userId)
    }
    
    public func deviceTrustLevel(forDevice deviceId: String!, ofUser userId: String!) -> MXDeviceTrustLevel! {
        guard let userId = userId, let deviceId = deviceId else {
            log.failure("Missing user id or device id")
            return nil
        }
        return trustLevelSource.deviceTrustLevel(userId: userId, deviceId: deviceId)
    }
    
    public func trustLevelSummary(
        forUserIds userIds: [String]!,
        forceDownload: Bool,
        success: ((MXUsersTrustLevelSummary?) -> Void)!,
        failure: ((Swift.Error?) -> Void)!
    ) {
        guard let userIds = userIds else {
            log.failure("Missing user ids")
            failure?(nil)
            return
        }
        
        _ = downloadKeys(userIds, forceDownload: forceDownload, success: { [weak self] _, _ in
            success?(
                self?.trustLevelSource.trustLevelSummary(userIds: userIds)
            )
        }, failure: failure)
    }
    
    public func setUserVerification(
        _ verificationStatus: Bool,
        forUser userId: String!,
        success: (() -> Void)!,
        failure: ((Swift.Error?) -> Void)!
    ) {
        guard let userId = userId else {
            log.failure("Missing user")
            failure?(nil)
            return
        }
        guard verificationStatus else {
            log.error("Unsetting trust not implemented")
            failure?(nil)
            return
        }
        
        log.debug("Setting user verification status manually")
        
        Task {
            do {
                try await machine.manuallyVerifyUser(userId: userId)
                log.debug("Successfully marked user as verified")
                await MainActor.run {
                    success?()
                }
            } catch {
                log.error("Failed marking user as verified", context: error)
                await MainActor.run {
                    failure?(error)
                }
            }
        }
    }
    
    public func setDeviceVerification(
        _ verificationStatus: MXDeviceVerification,
        forDevice deviceId: String!,
        ofUser userId: String!,
        success: (() -> Void)!,
        failure: ((Swift.Error?) -> Void)!
    ) {
        guard let userId = userId, let deviceId = deviceId else {
            log.failure("Missing user/device")
            failure?(nil)
            return
        }
        
        log.debug("Setting device verification status manually to \(verificationStatus)")
        
        let localTrust = verificationStatus.localTrust
        switch localTrust {
        case .verified:
            // If we want to set verified status, we will manually verify the device,
            // including uploading relevant signatures
            
            Task {
                do {
                    try await machine.manuallyVerifyDevice(userId: userId, deviceId: deviceId)
                    log.debug("Successfully marked device as verified")
                    await MainActor.run {
                        success?()
                    }
                } catch {
                    log.error("Failed marking device as verified", context: error)
                    await MainActor.run {
                        failure?(error)
                    }
                }
            }
            
        case .blackListed, .ignored, .unset:
            // In other cases we will only set local trust level
            
            do {
                try machine.setLocalTrust(userId: userId, deviceId: deviceId, trust: localTrust)
                log.debug("Successfully set local trust to \(localTrust)")
                success?()
            } catch {
                log.error("Failed setting local trust", context: error)
                failure?(error)
            }
        }
    }
    
    // MARK: - Users and devices
    
    public func eventDeviceInfo(_ event: MXEvent!) -> MXDeviceInfo! {
        guard
            let userId = event?.sender,
            let deviceId = event?.wireContent["device_id"] as? String
        else {
            log.failure("Missing user id or device id")
            return nil;
        }
        return device(withDeviceId: deviceId, ofUser: userId)
    }
    
    public func setDevicesKnown(_ devices: MXUsersDevicesMap<MXDeviceInfo>!, complete: (() -> Void)!) {
        log.debug("Not implemented")
    }
    
    public func downloadKeys(
        _ userIds: [String]!,
        forceDownload: Bool,
        success: ((MXUsersDevicesMap<MXDeviceInfo>?, [String: MXCrossSigningInfo]?) -> Void)!,
        failure: ((Swift.Error?) -> Void)!
    ) -> MXHTTPOperation! {
        guard let userIds = userIds else {
            log.failure("Missing user ids")
            return nil
        }
        
        guard forceDownload else {
            success?(
                deviceInfoSource.devicesMap(userIds: userIds),
                crossSigningInfo(userIds: userIds)
            )
            return MXHTTPOperation()
        }
        
        Task {
            do {
                try await machine.downloadKeys(users: userIds)
                await MainActor.run {
                    success?(
                        deviceInfoSource.devicesMap(userIds: userIds),
                        crossSigningInfo(userIds: userIds)
                    )
                }
            } catch {
                await MainActor.run {
                    failure?(error)
                }
            }
        }
        
        return MXHTTPOperation()
    }
    
    public func devices(forUser userId: String!) -> [String : MXDeviceInfo]! {
        guard let userId = userId else {
            log.failure("Missing user id")
            return [:]
        }
        return deviceInfoSource.devicesInfo(userId: userId)
    }
    
    public func device(withDeviceId deviceId: String!, ofUser userId: String!) -> MXDeviceInfo! {
        guard let userId = userId, let deviceId = deviceId else {
            log.failure("Missing user id or device id")
            return nil
        }
        return deviceInfoSource.deviceInfo(userId: userId, deviceId: deviceId)
    }
    
    public func resetReplayAttackCheck(inTimeline timeline: String!) {
        log.debug("Not implemented")
    }
    
    public func resetDeviceKeys() {
        log.debug("Not implemented")
    }
    
    public func requestAllPrivateKeys() {
        log.debug("Not implemented")
    }
    
    public func exportRoomKeys(
        withPassword password: String!,
        success: ((Data?) -> Void)!,
        failure: ((Swift.Error?) -> Void)!
    ) {
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            do {
                let data = try self.backupEngine.exportRoomKeys(passphrase: password)
                await MainActor.run {
                    self.log.debug("Exported room keys")
                    success(data)
                }
            } catch {
                await MainActor.run {
                    self.log.error("Failed exporting room keys", context: error)
                    failure(error)
                }
            }
        }
    }
    
    public func importRoomKeys(
        _ keyFile: Data!,
        withPassword password: String!,
        success: ((UInt, UInt) -> Void)!,
        failure: ((Swift.Error?) -> Void)!
    ) {
        guard let data = keyFile, let password = password else {
            log.failure("Missing keys or password")
            failure(nil)
            return
        }
        
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            do {
                let result = try self.backupEngine.importRoomKeys(data, passphrase: password)
                
                await MainActor.run {
                    self.retryUndecryptableEvents()
                    self.log.debug("Imported room keys")
                    success(UInt(result.total), UInt(result.imported))
                }
            } catch {
                await MainActor.run {
                    self.log.error("Failed importing room keys", context: error)
                    failure(error)
                }
            }
        }
    }
    
    public func pendingKeyRequests(_ onComplete: ((MXUsersDevicesMap<NSArray>?) -> Void)!) {
        // Not implemented, handled automatically by CryptoMachine
    }
    
    public func acceptAllPendingKeyRequests(fromUser userId: String!, andDevice deviceId: String!, onComplete: (() -> Void)!) {
        // Not implemented, handled automatically by CryptoMachine
    }
    
    public func ignoreAllPendingKeyRequests(fromUser userId: String!, andDevice deviceId: String!, onComplete: (() -> Void)!) {
        // Not implemented, handled automatically by CryptoMachine
    }
    
    public func setOutgoingKeyRequestsEnabled(_ enabled: Bool, onComplete: (() -> Void)!) {
        // Not implemented, handled automatically by CryptoMachine
    }
    
    public var enableOutgoingKeyRequestsOnceSelfVerificationDone: Bool {
        get {
            log.debug("Not implemented")
            return false
        }
        set {
            log.debug("Not implemented")
        }
    }
    
    public func reRequestRoomKey(for event: MXEvent!) {
        log.debug("->")
        
        guard let event = event else {
            log.failure("Missing event")
            return
        }
        undecryptableEvents[event.eventId] = event
        
        Task {
            log.debug("->")
            do {
                try await machine.requestRoomKey(event: event)
                await MainActor.run {
                    retryUndecryptableEvents()
                    
                    log.debug("Recieved room keys and re-decrypted event")
                }
            } catch {
                log.error("Failed requesting room key", context: error)
            }
        }
    }
    
    public var warnOnUnknowDevices: Bool {
        get {
            log.debug("Not implemented")
            return false
        }
        set {
            log.debug("Not implemented")
        }
    }
    
    public var globalBlacklistUnverifiedDevices: Bool {
        get {
            log.debug("Not implemented")
            return false
        }
        set {
            log.debug("Not implemented")
        }
    }
    
    public func isBlacklistUnverifiedDevices(inRoom roomId: String!) -> Bool {
        log.debug("Not implemented")
        return false
    }
    
    public func isRoomEncrypted(_ roomId: String!) -> Bool {
        guard let roomId = roomId, let summary = session?.room(withRoomId: roomId)?.summary else {
            log.error("Missing room")
            return false
        }
        // State of room encryption will be moved to MatrixSDKCrypto
        return summary.isEncrypted
    }
    
    public func setBlacklistUnverifiedDevicesInRoom(_ roomId: String!, blacklist: Bool) {
        log.debug("Not implemented")
    }
    
    // MARK: - Private
    
    private func getRoomUserIds(for room: MXRoom) async throws -> [String] {
        return try await room.members()?.members
            .compactMap(\.userId)
            .filter { $0 != machine.userId } ?? []
    }
    
    private func crossSigningInfo(userIds: [String]) -> [String: MXCrossSigningInfo] {
        return userIds
            .compactMap(crossSigning.crossSigningKeys(forUser:))
            .reduce(into: [String: MXCrossSigningInfo] ()) { dict, info in
                return dict[info.userId] = info
            }
    }
}

private extension MXDeviceVerification {
    var localTrust: LocalTrust {
        switch self {
        case .unverified:
            return .unset
        case .verified:
            return .verified
        case .blocked:
            return .blackListed
        case .unknown:
            return .unset
        @unknown default:
            MXNamedLog(name: "MXDeviceVerification").failure("Unknown device verification", context: self)
            return .unset
        }
    }
}

#endif

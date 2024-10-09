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

/// An implementation of `MXCrypto` which uses [matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk/tree/main/crates/matrix-sdk-crypto)
/// under the hood.
class MXCryptoV2: NSObject, MXCrypto {

    enum Error: Swift.Error {
        case cannotUnsetTrust
        case backupNotEnabled
    }
    
    // MARK: - Private properties
    
    private weak var session: MXSession?
    
    private let machine: MXCryptoMachine
    private let encryptor: MXRoomEventEncrypting
    private let decryptor: MXRoomEventDecrypting
    private let deviceInfoSource: MXDeviceInfoSource
    private let trustLevelSource: MXTrustLevelSource
    private let backupEngine: MXCryptoKeyBackupEngine?
    
    private let keyVerification: MXKeyVerificationManagerV2
    private var startTask: Task<(), Swift.Error>?
    private var roomEventObserver: Any?
    
    private let log = MXNamedLog(name: "MXCryptoV2")
    
    // MARK: - Public properties
    
    var version: String {
        return "Rust Crypto SDK \(MatrixSDKCrypto.version()) (Vodozemac \(MatrixSDKCrypto.vodozemacVersion()))"
    }
    
    var deviceCurve25519Key: String? {
        return machine.deviceCurve25519Key
    }
    
    var deviceEd25519Key: String? {
        return machine.deviceEd25519Key
    }
    
    var deviceCreationTs: UInt64 {
        // own device always exists
        return machine.device(userId: machine.userId, deviceId: machine.deviceId)!.firstTimeSeenTs
    }
    
    let backup: MXKeyBackup?
    let keyVerificationManager: MXKeyVerificationManager
    let crossSigning: MXCrossSigning
    let recoveryService: MXRecoveryService
    let dehydrationService: DehydrationService
    
    @MainActor
    init(
        userId: String,
        deviceId: String,
        session: MXSession,
        restClient: MXRestClient
    ) throws {
        self.session = session
        
        let getRoomAction: (String) -> MXRoom? = { [weak session] in
            session?.room(withRoomId: $0)
        }
        
        machine = try MXCryptoMachine(
            userId: userId,
            deviceId: deviceId,
            restClient: restClient,
            getRoomAction: getRoomAction
        )
        
        encryptor = MXRoomEventEncryption(
            handler: machine,
            getRoomAction: getRoomAction
        )
        decryptor = MXRoomEventDecryption(handler: machine)
        
        deviceInfoSource = MXDeviceInfoSource(source: machine)
        trustLevelSource = MXTrustLevelSource(
            userIdentitySource: machine,
            devicesSource: machine
        )
        
        keyVerification = MXKeyVerificationManagerV2(
            session: session,
            handler: machine
        )
        
        // Some functionality not yet migrated to the rust-sdk (e.g. backup state machine, 4S ...) uses
        // dispatch queues under the hood. We create one specific to crypto v2.
        let legacyQueue = DispatchQueue(label: "org.matrix.sdk.MXCryptoV2")
        
        if MXSDKOptions.sharedInstance().enableKeyBackupWhenStartingMXCrypto {
            let engine = MXCryptoKeyBackupEngine(backup: machine, roomEventDecryptor: decryptor)
            backupEngine = engine
            backup = MXKeyBackup(
                engine: engine,
                restClient: restClient,
                queue: legacyQueue
            )
        } else {
            backupEngine = nil
            backup = nil
        }
        
        keyVerificationManager = keyVerification
        
        let crossSign = MXCrossSigningV2(
            crossSigning: machine,
            restClient: restClient
        )
        crossSigning = crossSign
        
        let secretStorage = MXSecretStorage(matrixSession: session, processingQueue: legacyQueue)
        
        recoveryService = MXRecoveryService(
            dependencies: .init(
                credentials: restClient.credentials,
                backup: backup,
                secretStorage: secretStorage,
                secretStore: MXCryptoSecretStoreV2(
                    backup: backup,
                    backupEngine: backupEngine,
                    crossSigning: machine
                ),
                crossSigning: crossSigning,
                cryptoQueue: legacyQueue
            ),
            delegate: crossSign
        )
        
        dehydrationService = DehydrationService(restClient: restClient,
                                                secretStorage: secretStorage,
                                                dehydratedDevices: machine.dehydratedDevices())
        
        log.debug("Initialized Crypto module")
    }
    
    // MARK: - Crypto start / close
    
    func start(
        _ onComplete: (() -> Void)?,
        failure: ((Swift.Error) -> Void)?
    ) {
        log.debug("->")
        if startTask != nil {
            log.warning("Crypto module has already been started")
        }
        
        Task {
            do {
                try await start()
                
                log.debug("Crypto module started")
                await MainActor.run {
                    registerEventHandlers()
                    onComplete?()
                }
            } catch {
                log.error("Failed starting crypto module", context: error)
                await MainActor.run {
                    failure?(error)
                }
            }
        }
    }
    
    private func start() async throws {
        let task = startTask ?? .init {
            try await machine.uploadKeysIfNecessary()
            crossSigning.refreshState(success: nil)
            backup?.checkAndStart()
        }
        startTask = task
        return try await task.value
    }
    
    public func close(_ deleteStore: Bool) {
        log.debug("->")
        
        startTask?.cancel()
        startTask = nil
        
        session?.removeListener(roomEventObserver)
        Task {
            await decryptor.resetUndecryptedEvents()
        }
        
        if deleteStore {
            do {
                try machine.deleteAllData()
            } catch {
                log.failure("Cannot delete crypto store", context: error)
            }
        }
    }
    
    // MARK: - Event Encryption
    
    public func isRoomEncrypted(_ roomId: String) -> Bool {
        return encryptor.isRoomEncrypted(roomId: roomId)
    }
    
    func encryptEventContent(
        _ eventContent: [AnyHashable: Any],
        withType eventType: String,
        in room: MXRoom,
        success: (([AnyHashable: Any], String) -> Void)?,
        failure: ((Swift.Error) -> Void)?
    ) -> MXHTTPOperation? {
        log.debug("Encrypting content of type `\(eventType)`")
        
        let startDate = Date()
        let stopTracking =  MXSDKOptions.sharedInstance().analyticsDelegate?
            .startDurationTracking(forName: "MXCryptoV2", operation: "encryptEventContent")
        
        Task {
            do {
                let result = try await encryptor.encrypt(
                    content: eventContent,
                    eventType: eventType,
                    in: room
                )
                
                stopTracking?()
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
        return nil
    }
    
    func decryptEvents(
        _ events: [MXEvent],
        inTimeline timeline: String?,
        onComplete: (([MXEventDecryptionResult]) -> Void)?
    ) {
        guard session?.isEventStreamInitialised == true else {
            log.debug("Ignoring \(events.count) encrypted event(s) during initial sync (we most likely do not have the keys yet)")
            let results = events.map { _ in MXEventDecryptionResult() }
            onComplete?(results)
            return
        }
        
        Task {
            let results = await decryptor.decrypt(events: events)
            await MainActor.run {
                onComplete?(results)
            }
        }
    }
    
    func ensureEncryption(
        inRoom roomId: String,
        success: (() -> Void)?,
        failure: ((Swift.Error) -> Void)?
    ) -> MXHTTPOperation? {
        Task {
            do {
                try await encryptor.ensureRoomKeysShared(roomId: roomId)
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
        return nil
    }
    
    public func eventDeviceInfo(_ event: MXEvent) -> MXDeviceInfo? {
        guard
            let userId = event.sender,
            let deviceId = event.wireContent["device_id"] as? String
        else {
            log.error("Missing user id or device id")
            return nil;
        }
        return device(withDeviceId: deviceId, ofUser: userId)
    }
    
    public func discardOutboundGroupSessionForRoom(
        withRoomId roomId: String,
        onComplete: (() -> Void)?
    ) {
        log.debug("->")
        machine.discardRoomKey(roomId: roomId)
        onComplete?()
    }
    
    // MARK: - Sync
    
    func handle(_ syncResponse: MXSyncResponse, onComplete: @escaping () -> Void) {
        let syncId = UUID().uuidString
        let details = """
        Handling new sync response `\(syncId)`
          - to-device events : \(syncResponse.toDevice?.events.count ?? 0)
          - devices changed  : \(syncResponse.deviceLists?.changed?.count ?? 0)
          - devices left     : \(syncResponse.deviceLists?.left?.count ?? 0)
          - one time keys    : \(syncResponse.deviceOneTimeKeysCount?[kMXKeySignedCurve25519Type] ?? 0)
          - fallback keys    : \(syncResponse.unusedFallbackKeys ?? [])
        """
        log.debug(details)
        
        Task {
            do {
                let toDevice = try await machine.handleSyncResponse(
                    toDevice: syncResponse.toDevice,
                    deviceLists: syncResponse.deviceLists,
                    deviceOneTimeKeysCounts: syncResponse.deviceOneTimeKeysCount ?? [:],
                    unusedFallbackKeys: syncResponse.unusedFallbackKeys,
                    nextBatchToken: syncResponse.nextBatch
                )
                await handle(toDeviceEvents: toDevice.events)
            } catch {
                log.error("Cannot handle sync", context: error)
            }
            
            do {
                try await machine.processOutgoingRequests()
            } catch {
                log.error("Failed processing outgoing requests", context: error)
            }
            
            log.debug("Completed handling sync response `\(syncId)`")
            await MainActor.run {
                onComplete()
            }
        }
    }
    
    private func handle(toDeviceEvents: [MXEvent]) async {
        // Some of the to-device events processed by the machine require further updates
        // on the client side, not currently exposed through any convenient api.
        // These include new key verification events, or receiving backup key
        // which allows downloading room keys from backup.
        for event in toDeviceEvents {
            await keyVerification.handleDeviceEvent(event)
            restoreBackupIfPossible(event: event)
            await decryptor.handlePossibleRoomKeyEvent(event)
        }
        
        if backupEngine?.enabled == true && backupEngine?.hasKeysToBackup() == true {
            backup?.maybeSend()
        }
    }
    
    // MARK: - Cross-signing / Local trust
    
    public func setDeviceVerification(
        _ verificationStatus: MXDeviceVerification,
        forDevice deviceId: String,
        ofUser userId: String,
        success: (() -> Void)?,
        failure: ((Swift.Error) -> Void)?
    ) {
        log.debug("Setting device verification status to \(verificationStatus)")
        
        let localTrust = verificationStatus.localTrust
        switch localTrust {
        case .verified:
            // If we want to set verified status, we will manually verify the device,
            // including uploading relevant signatures
            try? machine.setLocalTrust(userId: machine.userId, deviceId: deviceId, trust: .verified)
            
            if (userId == machine.userId) {
                if (machine.crossSigningStatus().hasSelfSigning) {
                    // If we can cross sign, upload a new signature for that device
                    Task {
                        do {
                            try await machine.verifyDevice(userId: userId, deviceId: deviceId)
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
                } else {
                    // It's a good time to request secrets
                    Task {
                        do {
                            try await machine.queryMissingSecretsFromOtherSessions()
                            await MainActor.run {
                                success?()
                            }
                        } catch {
                            log.error("Failed to query missing secrets", context: error)
                            failure?(error)
                        }
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
    
    public func setUserVerification(
        _ verificationStatus: Bool,
        forUser userId: String,
        success: (() -> Void)?,
        failure: ((Swift.Error) -> Void)?
    ) {
        guard verificationStatus else {
            log.failure("Cannot unset user trust")
            failure?(Error.cannotUnsetTrust)
            return
        }
        
        log.debug("Signing user")
        crossSigning.signUser(
            withUserId: userId,
            success: {
                success?()
            },
            failure: {
                failure?($0)
            }
        )
    }
    
    public func trustLevel(forUser userId: String) -> MXUserTrustLevel {
        return trustLevelSource.userTrustLevel(userId: userId)
    }
    
    public func deviceTrustLevel(forDevice deviceId: String, ofUser userId: String) -> MXDeviceTrustLevel? {
        return trustLevelSource.deviceTrustLevel(userId: userId, deviceId: deviceId)
    }
    
    public func trustLevelSummary(
        forUserIds userIds: [String],
        forceDownload: Bool,
        success: ((MXUsersTrustLevelSummary?) -> Void)?,
        failure: ((Swift.Error) -> Void)?
    ) {
        _ = downloadKeys(
            userIds,
            // Force downloading keys is not recommended in crypto v2, and in particular when calculating
            // trust level summary, it is not necessary
            forceDownload: false,
            success: { [weak self] _, _ in
                success?(
                    self?.trustLevelSource.trustLevelSummary(userIds: userIds)
                )
            }, failure: failure)
    }
    
    // MARK: - Users keys

    public func downloadKeys(
        _ userIds: [String],
        forceDownload: Bool,
        success: ((MXUsersDevicesMap<MXDeviceInfo>?, [String: MXCrossSigningInfo]?) -> Void)?,
        failure: ((Swift.Error) -> Void)?
    ) -> MXHTTPOperation? {
        log.debug("->")
        
        Task {
            do {
                if forceDownload {
                    try await machine.reloadKeys(users: userIds)
                } else {
                    try await machine.downloadKeysIfNecessary(users: userIds)
                }
                
                log.debug("Downloaded keys")
                await MainActor.run {
                    success?(
                        deviceInfoSource.devicesMap(userIds: userIds),
                        crossSigningInfo(userIds: userIds)
                    )
                }
            } catch {
                log.error("Failed downloading keys", context: error)
                await MainActor.run {
                    failure?(error)
                }
            }
        }
        
        return nil
    }
    
    public func devices(forUser userId: String) -> [String : MXDeviceInfo] {
        return deviceInfoSource.devicesInfo(userId: userId)
    }
    
    public func device(withDeviceId deviceId: String, ofUser userId: String) -> MXDeviceInfo? {
        return deviceInfoSource.deviceInfo(userId: userId, deviceId: deviceId)
    }
    
    // MARK: - Import / Export
    
    public func exportRoomKeys(
        withPassword password: String,
        success: ((Data) -> Void)?,
        failure: ((Swift.Error) -> Void)?
    ) {
        log.debug("->")
        
        guard let engine = backupEngine else {
            log.failure("Cannot export keys when backup not enabled")
            failure?(Error.backupNotEnabled)
            return
        }
        
        Task {
            do {
                let data = try engine.exportRoomKeys(passphrase: password)
                await MainActor.run {
                    log.debug("Exported room keys")
                    success?(data)
                }
            } catch {
                await MainActor.run {
                    log.error("Failed exporting room keys", context: error)
                    failure?(error)
                }
            }
        }
    }
    
    public func importRoomKeys(
        _ keyFile: Data,
        withPassword password: String,
        success: ((UInt, UInt) -> Void)?,
        failure: ((Swift.Error) -> Void)?
    ) {
        log.debug("->")
        
        guard let engine = backupEngine else {
            log.failure("Cannot import keys when backup not enabled")
            failure?(Error.backupNotEnabled)
            return
        }
        
        Task {
            do {
                let result = try await engine.importRoomKeys(keyFile, passphrase: password)
                
                await MainActor.run {
                    log.debug("Imported room keys")
                    success?(UInt(result.total), UInt(result.imported))
                }
            } catch {
                await MainActor.run {
                    log.error("Failed importing room keys", context: error)
                    failure?(error)
                }
            }
        }
    }
    
    // MARK: - Key sharing
    
    public func reRequestRoomKey(for event: MXEvent) {
        log.debug("->")

        Task {
            do {
                try await machine.requestRoomKey(event: event)
                log.debug("Sent room key request")
            } catch {
                log.error("Failed requesting room key", context: error)
            }
        }
    }
    
    // MARK: - Crypto settings
    
    public var globalBlacklistUnverifiedDevices: Bool {
        get {
            return machine.onlyAllowTrustedDevices
        }
        set {
            machine.onlyAllowTrustedDevices = newValue
        }
    }
    
    public func isBlacklistUnverifiedDevices(inRoom roomId: String) -> Bool {
        return machine.roomSettings(roomId: roomId)?.onlyAllowTrustedDevices == true
    }
    
    public func setBlacklistUnverifiedDevicesInRoom(_ roomId: String, blacklist: Bool) {
        do {
            try machine.setOnlyAllowTrustedDevices(for: roomId, onlyAllowTrustedDevices: blacklist)
        } catch {
            log.error("Failed blocking unverified devices", context: error)
        }
    }
    
    // MARK: - Private
    
    private func registerEventHandlers() {
        guard let session = session else {
            return
        }
        
        let verificationTypes = MXKeyVerificationManagerV2.dmEventTypes
        let allTypes = verificationTypes + [.roomEncryption, .roomMember]
        
        roomEventObserver = session.listenToEvents(allTypes) { [weak self] event, direction, customObject in
            guard let self = self, direction == .forwards else {
                return
            }
            
            Task {
                do {
                    if event.eventType == .roomEncryption {
                        try await self.encryptor.handleRoomEncryptionEvent(event)

                    } else if event.eventType == .roomMember {
                        await self.handleRoomMemberEvent(event, roomState: customObject as? MXRoomState)
                        
                    } else if verificationTypes.contains(where: { $0.identifier == event.type }) {
                        try await self.keyVerification.handleRoomEvent(event)
                    }
                } catch {
                    self.log.error("Error handling event", context: error)
                }
            }
        }
    }
    
    private func handleRoomMemberEvent(_ event: MXEvent, roomState: MXRoomState?) async {
        guard
            let userId = event.stateKey, !machine.isUserTracked(userId: userId),
            let state = roomState,
            let member = state.members?.member(withUserId: userId)
        else {
            return
        }
        
        guard member.membership == .join || (member.membership == .invite && state.historyVisibility != .joined) else {
            return
        }
        
        log.debug("Tracking new user `\(userId)` due to \(member.membership) event")
        machine.updateTrackedUsers([userId])
    }
    
    private func restoreBackupIfPossible(event: MXEvent) {
        guard
            event.type == kMXEventTypeStringSecretSend
            && event.content?["name"] as? NSString == MXSecretId.keyBackup.takeUnretainedValue(),
            let secret = MXSecretShareSend(fromJSON: event.content)?.secret
        else {
            return
        }
        
        log.debug("Restoring backup after receiving backup key")
        
        guard
            let backupVersion = backup?.keyBackupVersion,
            let version = backupVersion.version else
        {
            log.error("There is not backup version to restore")
            return
        }
        
        let data = MXBase64Tools.data(fromBase64: secret)
        backupEngine?.savePrivateKey(data, version: version)
        
        log.debug("Restoring room keys")
        backup?.restore(usingPrivateKeyKeyBackup: backupVersion, room: nil, session: nil) { [weak self] total, imported in
            self?.log.debug("Restored \(imported) out of \(total) room keys")
        }
    }
    
    private func crossSigningInfo(userIds: [String]) -> [String: MXCrossSigningInfo] {
        return userIds
            .compactMap(crossSigning.crossSigningKeys(forUser:))
            .reduce(into: [String: MXCrossSigningInfo] ()) { dict, info in
                return dict[info.userId] = info
            }
    }
    
    func invalidateCache(_ done: @escaping () -> Void) {
        Task {
            // invalidating cache is not required for crypto v2 and is just here for conformance with the original crypto protocol
            await MainActor.run {
                done()
            }
        }
    }}

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
        
        guard let session = session else {
            log.failure("Cannot create crypto V2, missing session")
            return nil
        }
        
        do {
            return try MXCryptoV2(session: session)
        } catch {
            log.failure("Error creating crypto V2", context: error)
            return nil
        }
    }
}
#endif

#if DEBUG

import MatrixSDKCrypto

/// An implementation of `MXCrypto` which uses [matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk/tree/main/crates/matrix-sdk-crypto)
/// under the hood.
private class MXCryptoV2: NSObject, MXCrypto {
    enum Error: Swift.Error {
        case missingCredentials
        case missingRoom
        case roomNotEncrypted
        case cannotUnsetTrust
        case backupNotEnabled
    }
    
    // MARK: - Private properties
    
    private static let keyRotationPeriodMsgs: Int = 100
    private static let keyRotationPeriodSec: Int = 7 * 24 * 3600
    
    private weak var session: MXSession?
    private let cryptoQueue: DispatchQueue
    private let legacyStore: MXCryptoStore
    private let machine: MXCryptoMachine
    private let roomEventDecryptor: MXRoomEventDecrypting
    private let deviceInfoSource: MXDeviceInfoSource
    private let trustLevelSource: MXTrustLevelSource
    private let backupEngine: MXCryptoKeyBackupEngine?
    private let keyVerification: MXKeyVerificationManagerV2
    private var startTask: Task<(), Never>?
    private var roomEventObserver: Any?
    private let log = MXNamedLog(name: "MXCryptoV2")
    
    // MARK: - Public properties
    
    var version: String {
        guard let sdkVersion = Bundle(for: OlmMachine.self).infoDictionary?["CFBundleShortVersionString"] else {
            return "Matrix SDK Crypto"
        }
        return "Matrix SDK Crypto \(sdkVersion)"
    }
    
    var deviceCurve25519Key: String? {
        return machine.deviceCurve25519Key
    }
    
    var deviceEd25519Key: String? {
        return machine.deviceEd25519Key
    }
    
    let backup: MXKeyBackup?
    let keyVerificationManager: MXKeyVerificationManager
    let crossSigning: MXCrossSigning
    let recoveryService: MXRecoveryService
    
    init(session: MXSession) throws {
        guard
            let restClient = session.matrixRestClient,
            let credentials = session.credentials,
            let userId = credentials.userId,
            let deviceId = credentials.deviceId
        else {
            throw Error.missingCredentials
        }
        
        self.session = session
        self.cryptoQueue = DispatchQueue(label: "MXCryptoV2-\(userId)")
        
        // A few features (global untrusted users blacklist) are not yet implemented in `MatrixSDKCrypto`
        // so they have to be stored locally. Will be moved to `MatrixSDKCrypto` eventually
        if MXRealmCryptoStore.hasData(for: credentials) {
            self.legacyStore = MXRealmCryptoStore(credentials: credentials)
        } else {
            self.legacyStore = MXRealmCryptoStore.createStore(with: credentials)
        }
        
        machine = try MXCryptoMachine(
            userId: userId,
            deviceId: deviceId,
            restClient: restClient,
            getRoomAction: { [weak session] roomId in
                session?.room(withRoomId: roomId)
            }
        )
        
        roomEventDecryptor = MXRoomEventDecryption(handler: machine)
        
        deviceInfoSource = MXDeviceInfoSource(source: machine)
        trustLevelSource = MXTrustLevelSource(
            userIdentitySource: machine,
            devicesSource: machine
        )
        
        keyVerification = MXKeyVerificationManagerV2(
            session: session,
            handler: machine
        )
        
        if MXSDKOptions.sharedInstance().enableKeyBackupWhenStartingMXCrypto {
            let engine = MXCryptoKeyBackupEngine(backup: machine, roomEventDecryptor: roomEventDecryptor)
            backupEngine = engine
            backup = MXKeyBackup(
                engine: engine,
                restClient: restClient,
                secretShareManager: MXSecretShareManager(),
                queue: cryptoQueue
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
            delegate: crossSign
        )
        
        log.debug("Initialized Crypto module")
    }
    
    // MARK: - Crypto start / close
    
    func start(
        _ onComplete: (() -> Void)?,
        failure: ((Swift.Error) -> Void)?
    ) {
        guard startTask == nil else {
            log.error("Crypto module has already been started")
            onComplete?()
            return
        }
        
        log.debug("->")
        startTask = Task {
            do {
                try await machine.start()
                crossSigning.refreshState(success: nil)
                backup?.checkAndStart()
                
                log.debug("Crypto module started")
                await MainActor.run {
                    listenToRoomEvents()
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
    
    public func close(_ deleteStore: Bool) {
        log.debug("->")
        
        startTask?.cancel()
        startTask = nil
        
        session?.removeListener(roomEventObserver)
        Task {
            await roomEventDecryptor.resetUndecryptedEvents()
        }
        
        if deleteStore {
            if let credentials = session?.credentials {
                MXRealmCryptoStore.delete(with: credentials)
            } else {
                log.failure("Missing credentials, cannot delete store")
            }
            
            do {
                try machine.deleteAllData()
            } catch {
                log.failure("Cannot delete crypto store", context: error)
            }
        }
    }
    
    // MARK: - Event Encryption
    
    public func isRoomEncrypted(_ roomId: String) -> Bool {
        guard let summary = session?.room(withRoomId: roomId)?.summary else {
            log.error("Missing room")
            return false
        }
        // State of room encryption is not yet implemented in `MatrixSDKCrypto`
        // Will be moved to `MatrixSDKCrypto` eventually
        return summary.isEncrypted
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
        
        guard let roomId = room.roomId else {
            log.failure("Missing room id")
            failure?(Error.missingRoom)
            return nil
        }
        
        guard isRoomEncrypted(roomId) else {
            log.failure("Attempting to encrypt event in room without encryption")
            failure?(Error.roomNotEncrypted)
            return nil
        }
        
        Task {
            do {
                let users = try await getRoomUserIds(for: room)
                let settings = try encryptionSettings(for: room)
                try await machine.shareRoomKeysIfNecessary(
                    roomId: roomId,
                    users: users,
                    settings: settings
                )
                let result = try machine.encryptRoomEvent(
                    content: eventContent,
                    roomId: roomId,
                    eventType: eventType
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
            log.debug("Ignoring \(events.count) encrypted event(s) during initial sync in timeline \(timeline ?? "") (we most likely do not have the keys yet)")
            let results = events.map { _ in MXEventDecryptionResult() }
            onComplete?(results)
            return
        }
        
        Task {
            log.debug("Decrypting \(events.count) event(s) in timeline \(timeline ?? "")")
            let results = await roomEventDecryptor.decrypt(events: events)
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
        log.debug("->")
        
        guard let room = session?.room(withRoomId: roomId) else {
            log.failure("Missing room")
            failure?(Error.missingRoom)
            return nil
        }
        
        Task {
            do {
                let users = try await getRoomUserIds(for: room)
                let settings = try encryptionSettings(for: room)
                try await machine.shareRoomKeysIfNecessary(
                    roomId: roomId,
                    users: users,
                    settings: settings
                )
                
                log.debug("Room keys shared when necessary")
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
        let toDeviceCount = syncResponse.toDevice?.events.count ?? 0
        let devicesChanged = syncResponse.deviceLists?.changed?.count ?? 0
        let devicesLeft = syncResponse.deviceLists?.left?.count ?? 0
        
        MXLog.debug("[MXCryptoV2] --------------------------------")
        log.debug("Handling new sync response with \(toDeviceCount) to-device event(s), \(devicesChanged) device(s) changed, \(devicesLeft) device(s) left")
        
        Task {
            do {
                let toDevice = try machine.handleSyncResponse(
                    toDevice: syncResponse.toDevice,
                    deviceLists: syncResponse.deviceLists,
                    deviceOneTimeKeysCounts: syncResponse.deviceOneTimeKeysCount ?? [:],
                    unusedFallbackKeys: syncResponse.unusedFallbackKeys
                )
                await handle(toDeviceEvents: toDevice.events)
                try await machine.processOutgoingRequests()
            } catch {
                log.error("Cannot handle sync", context: error)
            }
            
            log.debug("Completing sync response")
            MXLog.debug("[MXCryptoV2] --------------------------------")
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
            await roomEventDecryptor.handlePossibleRoomKeyEvent(event)
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
        _ = downloadKeys(userIds, forceDownload: forceDownload, success: { [weak self] _, _ in
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
        
        guard forceDownload else {
            success?(
                deviceInfoSource.devicesMap(userIds: userIds),
                crossSigningInfo(userIds: userIds)
            )
            return nil
        }
        
        log.debug("Force-downloading keys")
        
        Task {
            do {
                try await machine.downloadKeys(users: userIds)
                
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
            return legacyStore.globalBlacklistUnverifiedDevices
        }
        set {
            legacyStore.globalBlacklistUnverifiedDevices = newValue
        }
    }
    
    public func isBlacklistUnverifiedDevices(inRoom roomId: String) -> Bool {
        return legacyStore.blacklistUnverifiedDevices(inRoom: roomId)
    }
    
    public func setBlacklistUnverifiedDevicesInRoom(_ roomId: String, blacklist: Bool) {
        legacyStore.storeBlacklistUnverifiedDevices(inRoom: roomId, blacklist: blacklist)
    }
    
    // MARK: - Private
    
    private func listenToRoomEvents() {
        guard let session = session else {
            return
        }
        
        roomEventObserver = session.listenToEvents(Array(MXKeyVerificationManagerV2.dmEventTypes)) { [weak self] event, direction, _ in
            guard let self = self else { return }
            
            if direction == .forwards && event.sender != session.myUserId {
                Task {
                    if let userId = await self.keyVerification.handleRoomEvent(event), !self.machine.isUserTracked(userId: userId) {
                        // If we recieved a verification event from a new user we do not yet track
                        // we need to download their keys to be able to proceed with the verification flow
                        try await self.machine.downloadKeys(users: [userId])
                    }
                }
            }
        }
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
    
    private func getRoomUserIds(for room: MXRoom) async throws -> [String] {
        return try await room.members()?.members
            .compactMap(\.userId) ?? []
    }
    
    private func crossSigningInfo(userIds: [String]) -> [String: MXCrossSigningInfo] {
        return userIds
            .compactMap(crossSigning.crossSigningKeys(forUser:))
            .reduce(into: [String: MXCrossSigningInfo] ()) { dict, info in
                return dict[info.userId] = info
            }
    }
    
    private func encryptionSettings(for room: MXRoom) throws -> EncryptionSettings {
        guard let roomId = room.roomId else {
            throw Error.missingRoom
        }
        
        let historyVisibility = try HistoryVisibility(identifier: room.summary.historyVisibility)
        return .init(
            algorithm: .megolmV1AesSha2,
            rotationPeriod: UInt64(Self.keyRotationPeriodSec),
            rotationPeriodMsgs: UInt64(Self.keyRotationPeriodMsgs),
            historyVisibility: historyVisibility,
            onlyAllowTrustedDevices: globalBlacklistUnverifiedDevices || isBlacklistUnverifiedDevices(inRoom: roomId)
        )
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

private extension HistoryVisibility {
    enum Error: Swift.Error {
        case invalidVisibility
    }
    
    init(identifier: String) throws {
        guard let visibility = MXRoomHistoryVisibility(identifier: identifier) else {
            throw Error.invalidVisibility
        }
        switch visibility {
        case .worldReadable:
            self = .worldReadable
        case .shared:
            self = .shared
        case .invited:
            self = .invited
        case .joined:
            self = .joined
        }
    }
}

#endif

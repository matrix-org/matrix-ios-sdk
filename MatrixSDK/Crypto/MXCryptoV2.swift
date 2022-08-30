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
public extension MXCrypto {
    /// Create a Rust-based work-in-progress subclass of `MXCrypto`
    ///
    /// The experimental crypto module is created only if:
    /// - using DEBUG build
    /// - running on iOS
    /// - enabling `enableCryptoV2` feature flag
    @objc static func createCryptoV2IfAvailable(session: MXSession!) -> MXCrypto? {
        let log = MXNamedLog(name: "MXCryptoV2")
        
        #if os(iOS)
            guard #available(iOS 13.0.0, *) else {
                return nil
            }
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
        #else
            return nil
        #endif
    }
}
#endif

#if DEBUG && os(iOS)

import MatrixSDKCrypto

/// A work-in-progress subclass of `MXCrypto` which uses [matrix-rust-sdk](https://github.com/matrix-org/matrix-rust-sdk/tree/main/crates/matrix-sdk-crypto)
/// under the hood.
///
/// This subclass serves as a skeleton to enable iterative implementation of matrix-rust-sdk without affecting existing
/// production code. It is a subclass because `MXCrypto` does not define a reusable protocol, and to define one would require
/// further risky refactors across the application.
///
/// Another benefit of using a subclass and overriding every method with new implementation is that existing integration tests
/// for crypto-related functionality can still run (and eventually pass) without any changes.
@available(iOS 13.0.0, *)
private class MXCryptoV2: MXCrypto {
    enum Error: Swift.Error {
        case missingRoom
    }
    
    public override var deviceCurve25519Key: String! {
        return machine.deviceCurve25519Key
    }
    
    public override var deviceEd25519Key: String! {
        return machine.deviceEd25519Key
    }
    
    public override var olmVersion: String! {
        log.debug("Not implemented")
        return nil
    }
    
    public override var backup: MXKeyBackup! {
        log.debug("Not implemented")
        return MXKeyBackup()
    }
    
    public override var keyVerificationManager: MXKeyVerificationManager! {
        return keyVerification
    }
    
    public override var recoveryService: MXRecoveryService! {
        log.debug("Not implemented")
        return MXRecoveryService()
    }
    
    public override var secretStorage: MXSecretStorage! {
        log.debug("Not implemented")
        return MXSecretStorage()
    }
    
    public override var secretShareManager: MXSecretShareManager! {
        log.debug("Not implemented")
        return MXSecretShareManager()
    }
    
    public override var crossSigning: MXCrossSigning! {
        return crossSign
    }
    
    private let userId: String
    private weak var session: MXSession?
    
    private let machine: MXCryptoMachine
    private let deviceInfoSource: MXDeviceInfoSource
    private let crossSigningInfoSource: MXCrossSigningInfoSource
    private let trustLevelSource: MXTrustLevelSource
    
    private let crossSign: MXCrossSigningV2
    private let keyVerification: MXKeyVerificationManagerV2
    
    private let log = MXNamedLog(name: "MXCryptoV2")
    
    public init(userId: String, deviceId: String, session: MXSession, restClient: MXRestClient) throws {
        self.userId = userId
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
        crossSigningInfoSource = MXCrossSigningInfoSource(source: machine)
        trustLevelSource = MXTrustLevelSource(
            userIdentitySource: machine,
            devicesSource: machine
        )
        
        crossSign = MXCrossSigningV2(
            crossSigning: machine,
            restClient: restClient
        )
        
        keyVerification = MXKeyVerificationManagerV2(
            verification: machine,
            getOrCreateDMRoomId: { [weak session] userId in
                // Note: assuming that DM already exists, fail otherwise. Will be updated in future PR
                guard let roomId = session?.directJoinedRoom(withUserId: userId)?.roomId else {
                    throw Error.missingRoom
                }
                return roomId
            }
        )
        
        super.init()
    }
    
    // MARK: - Factories
    
    public override class func createCrypto(withMatrixSession mxSession: MXSession!) -> MXCrypto! {
        MXNamedLog(name: "MXCryptoV2").debug("Not implemented")
        return nil
    }
    
    // MARK: - Class methods
    
    public override class func check(withMatrixSession mxSession: MXSession!, complete: ((MXCrypto?) -> Void)!) {
        MXNamedLog(name: "MXCryptoV2").debug("Not implemented")
    }
    
    public override class func rehydrateExportedOlmDevice(_ exportedOlmDevice: MXExportedOlmDevice!, with credentials: MXCredentials!, complete: ((Bool) -> Void)!) {
        MXNamedLog(name: "MXCryptoV2").debug("Not implemented")
    }
    
    // MARK: - Start / close
    
    public override func start(_ onComplete: (() -> Void)!, failure: ((Swift.Error?) -> Void)!) {
        onComplete?()
        log.debug("Not implemented")
    }
    
    public override func close(_ deleteStore: Bool) {
        if deleteStore {
            self.deleteStore(nil)
        }
    }
    
    // MARK: - Encrypt / Decrypt
    
    public override func encryptEventContent(
        _ eventContent: [AnyHashable : Any]!,
        withType eventType: String!,
        in room: MXRoom!,
        success: (([AnyHashable : Any]?, String?) -> Void)!,
        failure: ((Swift.Error?) -> Void)!
    ) -> MXHTTPOperation! {
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
                let result = try await machine.encrypt(
                    content,
                    roomId: roomId,
                    eventType: eventType,
                    users: users
                )
                
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
    
    public override func decryptEvent(
        _ event: MXEvent!,
        inTimeline timeline: String!
    ) -> MXEventDecryptionResult! {
        guard let event = event else {
            log.failure("Missing event")
            return nil
        }
        do {
            let result = try machine.decryptEvent(event)
            let type = result.clearEvent["type"] ?? ""
            log.debug("Decrypted event of type `\(type)`")
            
            return result
        } catch {
            log.error("Error decrypting event", context: error)
            let result = MXEventDecryptionResult()
            result.error = error
            return result
        }
    }
    
    public override func decryptEvents(
        _ events: [MXEvent]!,
        inTimeline timeline: String!,
        onComplete: (([MXEventDecryptionResult]?) -> Void)!
    ) {
        let results = events?.compactMap {
            decryptEvent($0, inTimeline: timeline)
        }
        onComplete?(results)
    }
    
    public override func ensureEncryption(
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
    
    public override func discardOutboundGroupSessionForRoom(withRoomId roomId: String!, onComplete: (() -> Void)!) {
        log.debug("Not implemented")
    }
    
    // MARK: - Sync
    
    public override func handle(_ syncResponse: MXSyncResponse!) {
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
        } catch {
            log.error("Cannot handle sync", context: error)
        }
    }
    
    public override func handleDeviceListsChanges(_ deviceLists: MXDeviceListResponse!) {
        // Not implemented, handled automatically by CryptoMachine
    }
    
    public override func handleDeviceOneTimeKeysCount(_ deviceOneTimeKeysCount: [String : NSNumber]!) {
        // Not implemented, handled automatically by CryptoMachine
    }
    
    public override func handleDeviceUnusedFallbackKeys(_ deviceUnusedFallbackKeys: [String]!) {
        // Not implemented, handled automatically by CryptoMachine
    }
    
    public override func handleRoomKeyEvent(_ event: MXEvent!, onComplete: (() -> Void)!) {
        // Not implemented, handled automatically by CryptoMachine
    }
    
    public override func onSyncCompleted(_ oldSyncToken: String!, nextSyncToken: String!, catchingUp: Bool) {
        Task {
            do {
                try await machine.completeSync()
            } catch {
                log.failure("Error processing outgoing requests", context: error)
            }
        }
    }
    
    // MARK: - Trust level
    
    public override func trustLevel(forUser userId: String!) -> MXUserTrustLevel! {
        guard let userId = userId else {
            log.failure("Missing user id")
            return nil
        }
        return trustLevelSource.userTrustLevel(userId: userId)
    }
    
    public override func deviceTrustLevel(forDevice deviceId: String!, ofUser userId: String!) -> MXDeviceTrustLevel! {
        guard let userId = userId, let deviceId = deviceId else {
            log.failure("Missing user id or device id")
            return nil
        }
        return trustLevelSource.deviceTrustLevel(userId: userId, deviceId: deviceId)
    }
    
    public override func trustLevelSummary(
        forUserIds userIds: [String]!,
        success: ((MXUsersTrustLevelSummary?) -> Void)!,
        failure: ((Swift.Error?) -> Void)!
    ) {
        guard let userIds = userIds else {
            log.failure("Missing user ids")
            failure?(nil)
            return
        }
        
        success?(
            trustLevelSource.trustLevelSummary(userIds: userIds)
        )
    }
    
    public override func trustLevelSummary(
        forUserIds userIds: [String]!,
        onComplete: ((MXUsersTrustLevelSummary?) -> Void)!
    ) {
        trustLevelSummary(
            forUserIds: userIds,
            success: onComplete,
            failure: { _ in
                onComplete?(nil)
            })
    }
    
    // MARK: - Users, devices and verification
    
    public override func eventDeviceInfo(_ event: MXEvent!) -> MXDeviceInfo! {
        guard
            let userId = event?.sender,
            let deviceId = event?.wireContent["device_id"] as? String
        else {
            log.failure("Missing user id or device id")
            return nil;
        }
        return device(withDeviceId: deviceId, ofUser: userId)
    }
    
    public override func setDeviceVerification(_ verificationStatus: MXDeviceVerification, forDevice deviceId: String!, ofUser userId: String!, success: (() -> Void)!, failure: ((Swift.Error?) -> Void)!) {
        log.debug("Not implemented")
    }
    
    public override func setDevicesKnown(_ devices: MXUsersDevicesMap<MXDeviceInfo>!, complete: (() -> Void)!) {
        log.debug("Not implemented")
    }
    
    public override func setUserVerification(_ verificationStatus: Bool, forUser userId: String!, success: (() -> Void)!, failure: ((Swift.Error?) -> Void)!) {
        log.debug("Not implemented")
    }
    
    public override func hasKeys(toDecryptEvent event: MXEvent!, onComplete: ((Bool) -> Void)!) {
        log.debug("Not implemented")
    }
    
    public override func downloadKeys(
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
                crossSigningInfoSource.crossSigningInfo(userIds: userIds)
            )
            return MXHTTPOperation()
        }
        
        Task {
            do {
                try await machine.downloadKeys(users: userIds)
                await MainActor.run {
                    success?(
                        deviceInfoSource.devicesMap(userIds: userIds),
                        crossSigningInfoSource.crossSigningInfo(userIds: userIds)
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
    
    public override func crossSigningKeys(forUser userId: String!) -> MXCrossSigningInfo! {
        guard let userId = userId else {
            log.failure("Missing user id")
            return nil
        }
        return crossSigningInfoSource.crossSigningInfo(userId: userId)
    }
    
    public override func devices(forUser userId: String!) -> [String : MXDeviceInfo]! {
        guard let userId = userId else {
            log.failure("Missing user id")
            return [:]
        }
        return deviceInfoSource.devicesInfo(userId: userId)
    }
    
    public override func device(withDeviceId deviceId: String!, ofUser userId: String!) -> MXDeviceInfo! {
        guard let userId = userId, let deviceId = deviceId else {
            log.failure("Missing user id or device id")
            return nil
        }
        return deviceInfoSource.deviceInfo(userId: userId, deviceId: deviceId)
    }
    
    public override func resetReplayAttackCheck(inTimeline timeline: String!) {
        log.debug("Not implemented")
    }
    
    public override func resetDeviceKeys() {
        log.debug("Not implemented")
    }
    
    public override func deleteStore(_ onComplete: (() -> Void)!) {
        do {
            try machine.deleteAllData()
        } catch {
            log.failure("Cannot delete crypto store", context: error)
        }
        onComplete?()
    }
    
    public override func requestAllPrivateKeys() {
        log.debug("Not implemented")
    }
    
    public override func exportRoomKeys(_ success: (([[AnyHashable : Any]]?) -> Void)!, failure: ((Swift.Error?) -> Void)!) {
        log.debug("Not implemented")
    }
    
    public override func exportRoomKeys(withPassword password: String!, success: ((Data?) -> Void)!, failure: ((Swift.Error?) -> Void)!) {
        log.debug("Not implemented")
    }
    
    public override func importRoomKeys(_ keys: [[AnyHashable : Any]]!, success: ((UInt, UInt) -> Void)!, failure: ((Swift.Error?) -> Void)!) {
        log.debug("Not implemented")
    }
    
    public override func importRoomKeys(_ keyFile: Data!, withPassword password: String!, success: ((UInt, UInt) -> Void)!, failure: ((Swift.Error?) -> Void)!) {
        log.debug("Not implemented")
    }
    
    public override func pendingKeyRequests(_ onComplete: ((MXUsersDevicesMap<NSArray>?) -> Void)!) {
        // Not implemented, handled automatically by CryptoMachine
    }
    
    public override func accept(_ keyRequest: MXIncomingRoomKeyRequest!, success: (() -> Void)!, failure: ((Swift.Error?) -> Void)!) {
        log.debug("Not implemented")
    }
    
    public override func acceptAllPendingKeyRequests(fromUser userId: String!, andDevice deviceId: String!, onComplete: (() -> Void)!) {
        log.debug("Not implemented")
    }
    
    public override func ignore(_ keyRequest: MXIncomingRoomKeyRequest!, onComplete: (() -> Void)!) {
        log.debug("Not implemented")
    }
    
    public override func ignoreAllPendingKeyRequests(fromUser userId: String!, andDevice deviceId: String!, onComplete: (() -> Void)!) {
        log.debug("Not implemented")
    }
    
    public override func setOutgoingKeyRequestsEnabled(_ enabled: Bool, onComplete: (() -> Void)!) {
        log.debug("Not implemented")
    }
    
    public override func isOutgoingKeyRequestsEnabled() -> Bool {
        log.debug("Not implemented")
        return false
    }
    
    public override var enableOutgoingKeyRequestsOnceSelfVerificationDone: Bool {
        get {
            log.debug("Not implemented")
            return false
        }
        set {
            log.debug("Not implemented")
        }
    }
    
    public override func reRequestRoomKey(for event: MXEvent!) {
        log.debug("Not implemented")
    }
    
    public override var warnOnUnknowDevices: Bool {
        get {
            log.debug("Not implemented")
            return false
        }
        set {
            log.debug("Not implemented")
        }
    }
    
    public override var globalBlacklistUnverifiedDevices: Bool {
        get {
            log.debug("Not implemented")
            return false
        }
        set {
            log.debug("Not implemented")
        }
    }
    
    public override func isBlacklistUnverifiedDevices(inRoom roomId: String!) -> Bool {
        log.debug("Not implemented")
        return false
    }
    
    public override func isRoomEncrypted(_ roomId: String!) -> Bool {
        log.debug("Not implemented")
        // All rooms encrypted by default for now
        return true
    }
    
    public override func isRoomSharingHistory(_ roomId: String!) -> Bool {
        log.debug("Not implemented")
        return false
    }
    
    public override func setBlacklistUnverifiedDevicesInRoom(_ roomId: String!, blacklist: Bool) {
        log.debug("Not implemented")
    }
    
    // MARK: - Private
    
    private func getRoomUserIds(for room: MXRoom) async throws -> [String] {
        return try await room.members()?.members
            .compactMap(\.userId)
            .filter { $0 != userId } ?? []
    }
}

#endif

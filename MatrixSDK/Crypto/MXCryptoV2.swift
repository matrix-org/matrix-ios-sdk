//
//  MXCryptoV2.swift
//  MatrixSDK
//
//  Created by Element on 11/05/2022.
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
                MXLog.error("[MXCryptoV2] Cannot create Crypto V2, missing properties")
                return nil
            }
            
            do {
                return try MXCryptoV2(userId: userId, deviceId: deviceId, session: session, restClient: restClient)
            } catch {
                MXLog.error("[MXCryptoV2] Error creating cryptoV2 \(error)")
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
    
    public override var deviceCurve25519Key: String! {
        return machine.deviceCurve25519Key
    }
    
    public override var deviceEd25519Key: String! {
        return machine.deviceEd25519Key
    }
    
    public override var olmVersion: String! {
        warnNotImplemented()
        return nil
    }
    
    public override var backup: MXKeyBackup! {
        warnNotImplemented()
        return nil
    }
    
    public override var keyVerificationManager: MXKeyVerificationManager! {
        warnNotImplemented()
        return nil
    }
    
    public override var recoveryService: MXRecoveryService! {
        warnNotImplemented()
        return nil
    }
    
    public override var secretStorage: MXSecretStorage! {
        warnNotImplemented()
        return nil
    }
    
    public override var secretShareManager: MXSecretShareManager! {
        warnNotImplemented()
        return nil
    }
    
    public override var crossSigning: MXCrossSigning! {
        warnNotImplemented()
        return nil
    }
    
    
    private let userId: String
    private weak var session: MXSession?
    private let machine: MXCryptoMachine
    
    public init(userId: String, deviceId: String, session: MXSession, restClient: MXRestClient) throws {
        self.userId = userId
        self.session = session
        machine = try MXCryptoMachine(
            userId: userId,
            deviceId: deviceId,
            restClient: restClient
        )
        
        super.init()
    }
    
    // MARK: - Factories
    
    public override class func createCrypto(withMatrixSession mxSession: MXSession!) -> MXCrypto! {
        warnNotImplemented()
        return nil
    }
    
    public override class func check(withMatrixSession mxSession: MXSession!, complete: ((MXCrypto?) -> Void)!) {
        warnNotImplemented()
    }
    
    public override class func rehydrateExportedOlmDevice(_ exportedOlmDevice: MXExportedOlmDevice!, with credentials: MXCredentials!, complete: ((Bool) -> Void)!) {
        warnNotImplemented()
    }
    
    // MARK: - Start / close
    
    public override func start(_ onComplete: (() -> Void)!, failure: ((Error?) -> Void)!) {
        onComplete?()
        warnNotImplemented()
    }
    
    public override func close(_ deleteStore: Bool) {
        warnNotImplemented()
    }
    
    // MARK: - Encrypt / Decrypt
    
    public override func encryptEventContent(
        _ eventContent: [AnyHashable : Any]!,
        withType eventType: String!,
        in room: MXRoom!,
        success: (([AnyHashable : Any]?, String?) -> Void)!,
        failure: ((Error?) -> Void)!
    ) -> MXHTTPOperation! {
        guard let content = eventContent, let eventType = eventType, let roomId = room.roomId else {
            MXLog.debug("[MXCryptoV2] encryptEventContent: Missing data to encrypt")
            return nil
        }
        
        guard isRoomEncrypted(roomId) else {
            MXLog.error("[MXCryptoV2] encryptEventContent: attempting to encrypt event in room without encryption")
            return nil
        }
        
        MXLog.debug("[MXCryptoV2] encryptEventContent: Encrypting content")
        
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
                MXLog.error("[MXCryptoV2] encryptEventContent: Error encrypting content - \(error)")
                await MainActor.run {
                    failure?(error)
                }
            }
        }
        return MXHTTPOperation()
    }
    
    public override func hasKeys(toDecryptEvent event: MXEvent!, onComplete: ((Bool) -> Void)!) {
        warnNotImplemented()
    }
    
    public override func decryptEvent(_ event: MXEvent!, inTimeline timeline: String!) -> MXEventDecryptionResult! {
        guard let event = event else {
            MXLog.debug("[MXCryptoV2] Missing event")
            return nil
        }
        do {
            return try machine.decryptEvent(event)
        } catch {
            MXLog.error("[MXCryptoV2] decryptEvent: \(error)")
            let result = MXEventDecryptionResult()
            result.error = error
            return result
        }
    }
    
    public override func decryptEvents(_ events: [MXEvent]!, inTimeline timeline: String!, onComplete: (([MXEventDecryptionResult]?) -> Void)!) {
        let results = events?.compactMap {
            decryptEvent($0, inTimeline: timeline)
        }
        onComplete?(results)
    }
    
    public override func ensureEncryption(inRoom roomId: String!, success: (() -> Void)!, failure: ((Error?) -> Void)!) -> MXHTTPOperation! {
        guard let roomId = roomId, let room = session?.room(withRoomId: roomId) else {
            MXLog.debug("[MXCryptoV2] ensureEncryption: Missing room")
            return nil
        }
        
        Task {
            do {
                let users = try await getRoomUserIds(for: room)
                try await machine.ensureOlmChanel(roomId: roomId, users: users)
                await MainActor.run {
                    success?()
                }
            } catch {
                MXLog.error("[MXCryptoV2] encryptEventContent: Error ensuring encryption - \(error)")
                await MainActor.run {
                    failure?(error)
                }
            }
        }
        
        return MXHTTPOperation()
    }
    
    public override func discardOutboundGroupSessionForRoom(withRoomId roomId: String!, onComplete: (() -> Void)!) {
        warnNotImplemented()
    }
    
    // MARK: - Sync
    
    public override func handle(_ syncResponse: MXSyncResponse!) {
        do {
            try machine.handleSyncResponse(
                toDevice: syncResponse.toDevice,
                deviceLists: syncResponse.deviceLists,
                deviceOneTimeKeysCounts: syncResponse.deviceOneTimeKeysCount ?? [:],
                unusedFallbackKeys: syncResponse.unusedFallbackKeys
            )
        } catch {
            MXLog.error("[MXCryptoV2] handleSyncResponse: \(error)")
        }
    }
    
    public override func handleDeviceListsChanges(_ deviceLists: MXDeviceListResponse!) {
        // Not implemented, will be handled by Rust
        warnNotImplemented(ignore: true)
    }
    
    public override func handleDeviceOneTimeKeysCount(_ deviceOneTimeKeysCount: [String : NSNumber]!) {
        // Not implemented, will be handled by Rust
        warnNotImplemented(ignore: true)
    }
    
    public override func handleDeviceUnusedFallbackKeys(_ deviceUnusedFallbackKeys: [String]!) {
        // Not implemented, will be handled by Rust
        warnNotImplemented(ignore: true)
    }
    
    public override func handleRoomKeyEvent(_ event: MXEvent!, onComplete: (() -> Void)!) {
        // Not implemented, will be handled by Rust
        warnNotImplemented(ignore: true)
    }
    
    public override func onSyncCompleted(_ oldSyncToken: String!, nextSyncToken: String!, catchingUp: Bool) {
        do {
            try machine.processOutgoingRequests()
        } catch {
            MXLog.error("[MXCryptoV2] onSyncCompleted: error processing outgoing requests \(error)")
        }
    }
    
    // MARK: - Devices
    
    public override func eventDeviceInfo(_ event: MXEvent!) -> MXDeviceInfo! {
        warnNotImplemented()
        return nil
    }
    
    public override func setDeviceVerification(_ verificationStatus: MXDeviceVerification, forDevice deviceId: String!, ofUser userId: String!, success: (() -> Void)!, failure: ((Error?) -> Void)!) {
        warnNotImplemented()
    }
    
    public override func setDevicesKnown(_ devices: MXUsersDevicesMap<MXDeviceInfo>!, complete: (() -> Void)!) {
        warnNotImplemented()
    }
    
    // MARK: - Other
    
    public override func setUserVerification(_ verificationStatus: Bool, forUser userId: String!, success: (() -> Void)!, failure: ((Error?) -> Void)!) {
        warnNotImplemented()
    }
    
    public override func trustLevel(forUser userId: String!) -> MXUserTrustLevel! {
        warnNotImplemented()
        return nil
    }
    
    public override func deviceTrustLevel(forDevice deviceId: String!, ofUser userId: String!) -> MXDeviceTrustLevel! {
        warnNotImplemented()
        return nil
    }
    
    public override func trustLevelSummary(forUserIds userIds: [String]!, success: ((MXUsersTrustLevelSummary?) -> Void)!, failure: ((Error?) -> Void)!) {
        warnNotImplemented()
    }
    
    public override func trustLevelSummary(forUserIds userIds: [String]!, onComplete: ((MXUsersTrustLevelSummary?) -> Void)!) {
        warnNotImplemented()
    }
    
    public override func downloadKeys(_ userIds: [String]!, forceDownload: Bool, success: ((MXUsersDevicesMap<MXDeviceInfo>?, [String : MXCrossSigningInfo]?) -> Void)!, failure: ((Error?) -> Void)!) -> MXHTTPOperation! {
        warnNotImplemented()
        return nil
    }
    
    public override func crossSigningKeys(forUser userId: String!) -> MXCrossSigningInfo! {
        warnNotImplemented()
        return nil
    }
    
    public override func devices(forUser userId: String!) -> [String : MXDeviceInfo]! {
        warnNotImplemented()
        return nil
    }
    
    public override func device(withDeviceId deviceId: String!, ofUser userId: String!) -> MXDeviceInfo! {
        warnNotImplemented()
        return nil
    }
    
    public override func resetReplayAttackCheck(inTimeline timeline: String!) {
        warnNotImplemented()
    }
    
    public override func resetDeviceKeys() {
        warnNotImplemented()
    }
    
    public override func deleteStore(_ onComplete: (() -> Void)!) {
        warnNotImplemented()
    }
    
    public override func requestAllPrivateKeys() {
        warnNotImplemented()
    }
    
    public override func exportRoomKeys(_ success: (([[AnyHashable : Any]]?) -> Void)!, failure: ((Error?) -> Void)!) {
        warnNotImplemented()
    }
    
    public override func exportRoomKeys(withPassword password: String!, success: ((Data?) -> Void)!, failure: ((Error?) -> Void)!) {
        warnNotImplemented()
    }
    
    public override func importRoomKeys(_ keys: [[AnyHashable : Any]]!, success: ((UInt, UInt) -> Void)!, failure: ((Error?) -> Void)!) {
        warnNotImplemented()
    }
    
    public override func importRoomKeys(_ keyFile: Data!, withPassword password: String!, success: ((UInt, UInt) -> Void)!, failure: ((Error?) -> Void)!) {
        warnNotImplemented()
    }
    
    public override func pendingKeyRequests(_ onComplete: ((MXUsersDevicesMap<NSArray>?) -> Void)!) {
        // Not implemented, will be handled by Rust
        warnNotImplemented(ignore: true)
    }
    
    public override func accept(_ keyRequest: MXIncomingRoomKeyRequest!, success: (() -> Void)!, failure: ((Error?) -> Void)!) {
        warnNotImplemented()
    }
    
    public override func acceptAllPendingKeyRequests(fromUser userId: String!, andDevice deviceId: String!, onComplete: (() -> Void)!) {
        warnNotImplemented()
    }
    
    public override func ignore(_ keyRequest: MXIncomingRoomKeyRequest!, onComplete: (() -> Void)!) {
        warnNotImplemented()
    }
    
    public override func ignoreAllPendingKeyRequests(fromUser userId: String!, andDevice deviceId: String!, onComplete: (() -> Void)!) {
        warnNotImplemented()
    }
    
    public override func setOutgoingKeyRequestsEnabled(_ enabled: Bool, onComplete: (() -> Void)!) {
        warnNotImplemented()
    }
    
    public override func isOutgoingKeyRequestsEnabled() -> Bool {
        warnNotImplemented()
        return false
    }
    
    public override var enableOutgoingKeyRequestsOnceSelfVerificationDone: Bool {
        get {
            warnNotImplemented()
            return false
        }
        set {
            warnNotImplemented()
        }
    }
    
    public override func reRequestRoomKey(for event: MXEvent!) {
        warnNotImplemented()
    }
    
    public override var warnOnUnknowDevices: Bool {
        get {
            warnNotImplemented()
            return false
        }
        set {
            warnNotImplemented()
        }
    }
    
    public override var globalBlacklistUnverifiedDevices: Bool {
        get {
            warnNotImplemented()
            return false
        }
        set {
            warnNotImplemented()
        }
    }
    
    public override func isBlacklistUnverifiedDevices(inRoom roomId: String!) -> Bool {
        warnNotImplemented()
        return false
    }
    
    public override func isRoomEncrypted(_ roomId: String!) -> Bool {
        warnNotImplemented()
        // All rooms encrypted by default for now
        return true
    }
    
    public override func isRoomSharingHistory(_ roomId: String!) -> Bool {
        warnNotImplemented()
        return false
    }
    
    public override func setBlacklistUnverifiedDevicesInRoom(_ roomId: String!, blacklist: Bool) {
        warnNotImplemented()
    }
    
    // MARK: - Private
    
    private func getRoomUserIds(for room: MXRoom) async throws -> [String] {
        return try await room.members()?.members
            .compactMap(\.userId)
            .filter { $0 != userId } ?? []
    }
    
    
    /// Convenience function which logs methods that are being called by the application,
    /// but are not yet implemented via the Rust component.
    private static func warnNotImplemented(ignore: Bool = false, _ function: String = #function) {
        MXLog.debug("[MXCryptoV2] function `\(function)` not implemented, ignored: \(ignore)")
    }
    
    private func warnNotImplemented(ignore: Bool = false, _ function: String = #function) {
        Self.warnNotImplemented(ignore: ignore, function)
    }
}

#endif

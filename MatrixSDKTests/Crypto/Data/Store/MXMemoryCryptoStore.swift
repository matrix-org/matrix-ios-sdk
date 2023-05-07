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
@_implementationOnly import OLMKit

public class MXMemoryCryptoStore: NSObject, MXCryptoStore {

    private static var stores: [MXCredentials: MXMemoryCryptoStore] = [:]

    private let credentials: MXCredentials
    private var storeAccount: Account?
    private var devices: [String: [MXDeviceInfo]] = [:]
    private var algorithms: [String: RoomAlgorithm] = [:]
    private var inboundSessions: [InboundSession] = []
    private var outboundSessions: [String: MXOlmOutboundGroupSession] = [:]
    private var secrets: [String: String] = [:]
    private var incomingRoomKeyRequestsMap: [String: MXIncomingRoomKeyRequest] = [:]
    private var outgoingRoomKeyRequests: [String: MXOutgoingRoomKeyRequest] = [:]
    private var olmSessions: [OlmSessionMapKey: MXOlmSession] = [:]
    private var crossSigningKeysMap: [String: MXCrossSigningInfo] = [:]
    private var sharedOutboundSessions: [SharedOutboundSession] = []

    // MARK: - MXCryptoStore

    public required init!(credentials: MXCredentials!) {
        self.credentials = credentials
        storeAccount = Account()
        storeAccount?.userId = credentials.userId
        storeAccount?.deviceId = credentials.deviceId
        storeAccount?.cryptoVersion = MXCryptoVersion(rawValue: MXCryptoVersion.versionCount.rawValue - 1) ?? .versionUndefined
        super.init()
    }

    public static func hasData(for credentials: MXCredentials!) -> Bool {
        stores[credentials] != nil
    }

    public static func createStore(with credentials: MXCredentials!) -> Self! {
        if let existingStore = stores[credentials] as? Self {
            return existingStore
        }
        if let newStore = Self(credentials: credentials) {
            stores[credentials] = newStore
            return newStore
        }
        return nil
    }

    public static func delete(with credentials: MXCredentials!) {
        stores.removeValue(forKey: credentials)
    }

    public static func deleteAllStores() {
        stores.removeAll()
    }

    public static func deleteReadonlyStore(with credentials: MXCredentials!) {
        // no-op
    }
    
    // MARK: - User ID
    
    public func userId() -> String! {
        storeAccount?.userId
    }

    // MARK: - Device ID

    public func storeDeviceId(_ deviceId: String!) {
        storeAccount?.deviceId = deviceId
    }

    public func deviceId() -> String! {
        storeAccount?.deviceId
    }

    // MARK: - Account

    public func setAccount(_ account: OLMAccount!) {
        storeAccount?.olmAccount = account
    }

    public func account() -> OLMAccount! {
        storeAccount?.olmAccount
    }

    public func performAccountOperation(_ block: ((OLMAccount?) -> Void)!) {
        block?(storeAccount?.olmAccount)
    }

    // MARK: - Device Sync Token

    public func storeDeviceSyncToken(_ deviceSyncToken: String!) {
        storeAccount?.deviceSyncToken = deviceSyncToken
    }

    public func deviceSyncToken() -> String! {
        storeAccount?.deviceSyncToken
    }

    // MARK: - Devices

    public func storeDevice(forUser userId: String!, device: MXDeviceInfo!) {
        if devices[userId] == nil {
            devices[userId] = []
        }
        devices[userId]?.append(device)
    }

    public func device(withDeviceId deviceId: String!, forUser userId: String!) -> MXDeviceInfo! {
        devices[userId]?.first { $0.deviceId == deviceId }
    }

    public func device(withIdentityKey identityKey: String!) -> MXDeviceInfo! {
        Array(devices.values).flatMap { $0 }.first { $0.identityKey == identityKey }
    }

    public func storeDevices(forUser userId: String!, devices: [String : MXDeviceInfo]!) {
        if self.devices[userId] != nil {
            // Reset all previously stored devices for this user
            self.devices.removeValue(forKey: userId)
        }

        self.devices[userId] = Array(devices.values)
    }

    public func devices(forUser userId: String!) -> [String : MXDeviceInfo]! {
        let devices = devices[userId] ?? []

        var result: [String: MXDeviceInfo] = [:]

        for device in devices {
            result[device.deviceId] = device
        }

        return result
    }

    // MARK: - Device Tracking Status

    public func deviceTrackingStatus() -> [String : NSNumber]! {
        storeAccount?.deviceTrackingStatus
    }

    public func storeDeviceTrackingStatus(_ statusMap: [String : NSNumber]!) {
        storeAccount?.deviceTrackingStatus = statusMap
    }

    // MARK: - Cross Signing Keys

    public func storeCrossSigningKeys(_ crossSigningInfo: MXCrossSigningInfo!) {
        crossSigningKeysMap[crossSigningInfo.userId] = crossSigningInfo
    }

    public func crossSigningKeys(forUser userId: String!) -> MXCrossSigningInfo! {
        crossSigningKeysMap[userId]
    }

    public func crossSigningKeys() -> [MXCrossSigningInfo]! {
        Array(crossSigningKeysMap.values)
    }

    // MARK: - Room Algorithm

    public func storeAlgorithm(forRoom roomId: String!, algorithm: String!) {
        algorithms[roomId] = RoomAlgorithm(algorithm: algorithm)
    }

    public func algorithm(forRoom roomId: String!) -> String! {
        algorithms[roomId]?.algorithm
    }
    
    // MARK: - Room Settings
    
    public func roomSettings() -> [MXRoomSettings]! {
        return algorithms.compactMap { roomId, item in
            do {
                return try MXRoomSettings(
                    roomId: roomId,
                    algorithm: item.algorithm,
                    blacklistUnverifiedDevices: item.blacklistUnverifiedDevices
                )
            } catch {
                MXLog.debug("[MXMemoryCryptoStore] roomSettings: Failed creating algorithm", context: error)
                return nil
            }
        }
    }

    // MARK: - OLM Session

    public func store(_ session: MXOlmSession!) {
        let key = OlmSessionMapKey(sessionId: session.session.sessionIdentifier(), deviceKey: session.deviceKey)
        olmSessions[key] = session
    }

    public func session(withDevice deviceKey: String!, andSessionId sessionId: String!) -> MXOlmSession! {
        let key = OlmSessionMapKey(sessionId: sessionId, deviceKey: deviceKey)
        return olmSessions[key]
    }

    public func performSessionOperation(withDevice deviceKey: String!, andSessionId sessionId: String!, block: ((MXOlmSession?) -> Void)!) {
        let session = session(withDevice: deviceKey, andSessionId: sessionId)
        block?(session)
    }

    public func sessions(withDevice deviceKey: String!) -> [MXOlmSession]! {
        Array(olmSessions.filter { $0.key.deviceKey == deviceKey }.values)
    }
    
    public func enumerateSessions(by batchSize: Int, block: (([MXOlmSession]?, Double) -> Void)!) {
        block(Array(olmSessions.values), 1)
    }
    
    public func sessionsCount() -> UInt {
        UInt(olmSessions.count)
    }

    // MARK: - Inbound Group Sessions

    public func store(_ sessions: [MXOlmInboundGroupSession]!) {
        inboundSessions.append(contentsOf: sessions.map { InboundSession(session: $0) } )
    }

    public func inboundGroupSession(withId sessionId: String!, andSenderKey senderKey: String!) -> MXOlmInboundGroupSession! {
        inboundSessions.first { $0.sessionId == sessionId && $0.session.senderKey == senderKey }?.session
    }

    public func performSessionOperationWithGroupSession(withId sessionId: String!, senderKey: String!, block: ((MXOlmInboundGroupSession?) -> Void)!) {
        let session = inboundGroupSession(withId: sessionId, andSenderKey: senderKey)
        block?(session)
    }

    public func inboundGroupSessions() -> [MXOlmInboundGroupSession]! {
        inboundSessions.map { $0.session }
    }
    
    public func enumerateInboundGroupSessions(by batchSize: Int, block: (([MXOlmInboundGroupSession]?, Set<String>?, Double) -> Void)!) {
        let backedUp = inboundSessions.filter { $0.backedUp }.map(\.sessionId)
        block(inboundGroupSessions(), Set(backedUp), 1)
    }

    public func inboundGroupSessions(withSessionId sessionId: String!) -> [MXOlmInboundGroupSession]! {
        inboundSessions.filter { $0.sessionId == sessionId }.map { $0.session }
    }

    public func removeInboundGroupSession(withId sessionId: String!, andSenderKey senderKey: String!) {
        inboundSessions.removeAll { $0.sessionId == sessionId && $0.session.senderKey == senderKey }
    }

    // MARK: - Outbound Group Sessions

    public func store(_ session: OLMOutboundGroupSession!, withRoomId roomId: String!) -> MXOlmOutboundGroupSession! {
        let creationTime: TimeInterval

        if let existingSession = outboundSessions[roomId],
           existingSession.sessionId == session.sessionIdentifier() {
            // Update the existing one
            creationTime = existingSession.creationTime
        } else {
            creationTime = Date().timeIntervalSince1970
        }

        if let newSession = MXOlmOutboundGroupSession(session: session, roomId: roomId, creationTime: creationTime) {
            outboundSessions[roomId] = newSession
            return newSession
        }

        return nil
    }

    public func outboundGroupSession(withRoomId roomId: String!) -> MXOlmOutboundGroupSession! {
        outboundSessions[roomId]
    }

    public func outboundGroupSessions() -> [MXOlmOutboundGroupSession]! {
        Array(outboundSessions.values)
    }

    public func removeOutboundGroupSession(withRoomId roomId: String!) {
        outboundSessions.removeValue(forKey: roomId)
    }

    // MARK: - Shared Devices

    public func storeSharedDevices(_ devices: MXUsersDevicesMap<NSNumber>!, messageIndex: UInt, forOutboundGroupSessionInRoomWithId roomId: String!, sessionId: String!) {
        for userId in devices.userIds() {
            for deviceId in devices.deviceIds(forUser: userId) {
                guard let device = device(withDeviceId: deviceId, forUser: userId) else {
                    continue
                }

                let session = SharedOutboundSession(roomId: roomId, sessionId: sessionId, device: device, messageIndex: messageIndex)
                sharedOutboundSessions.append(session)
            }
        }
    }

    public func sharedDevicesForOutboundGroupSessionInRoom(withId roomId: String!, sessionId: String!) -> MXUsersDevicesMap<NSNumber>! {
        let result = MXUsersDevicesMap<NSNumber>()

        let sessions = sharedOutboundSessions.filter { $0.roomId == roomId && $0.sessionId == sessionId }

        for session in sessions {
            result.setObject(NSNumber(value: session.messageIndex),
                             forUser: session.device.userId,
                             andDevice: session.device.deviceId)
        }

        return result
    }

    public func messageIndexForSharedDeviceInRoom(withId roomId: String!, sessionId: String!, userId: String!, deviceId: String!) -> NSNumber! {
        guard let index = sharedOutboundSessions.first(where: { $0.roomId == roomId
            && $0.sessionId == sessionId
            && $0.device.deviceId == deviceId })?.messageIndex else {
            return nil
        }
        return NSNumber(value: index)
    }

    // MARK: - Backup Markers

    public var backupVersion: String! {
        get {
            storeAccount?.backupVersion
        } set {
            storeAccount?.backupVersion = newValue
        }
    }

    public func resetBackupMarkers() {
        inboundSessions.forEach { $0.backedUp = false }
    }

    public func markBackupDone(for sessions: [MXOlmInboundGroupSession]!) {
        for session in sessions {
            inboundSessions.filter({ $0.sessionId == session.session.sessionIdentifier() }).forEach { $0.backedUp = true }
        }
    }

    public func inboundGroupSessions(toBackup limit: UInt) -> [MXOlmInboundGroupSession]! {
        let toBackup = inboundSessions.filter { !$0.backedUp }
        if toBackup.isEmpty {
            return []
        }
        let toDrop = toBackup.count > limit ? toBackup.count - Int(limit) : 0
        return toBackup.dropLast(toDrop).map { $0.session }
    }

    public func inboundGroupSessionsCount(_ onlyBackedUp: Bool) -> UInt {
        UInt(onlyBackedUp ? inboundSessions.filter { $0.backedUp }.count : inboundSessions.count)
    }

    // MARK: - Outgoing Room Key Requests

    public func outgoingRoomKeyRequest(withRequestBody requestBody: [AnyHashable : Any]!) -> MXOutgoingRoomKeyRequest! {
        outgoingRoomKeyRequests.first(where: { NSDictionary(dictionary: $1.requestBody).isEqual(to: requestBody) })?.value
    }

    public func outgoingRoomKeyRequest(with state: MXRoomKeyRequestState) -> MXOutgoingRoomKeyRequest! {
        outgoingRoomKeyRequests.first(where: { $0.value.state == state })?.value
    }

    public func allOutgoingRoomKeyRequests(with state: MXRoomKeyRequestState) -> [MXOutgoingRoomKeyRequest]! {
        Array(outgoingRoomKeyRequests.filter { $1.state == state }.values)
    }

    public func allOutgoingRoomKeyRequests(withRoomId roomId: String!, sessionId: String!, algorithm: String!, senderKey: String!) -> [MXOutgoingRoomKeyRequest]! {
        Array(outgoingRoomKeyRequests.filter {
            $1.roomId == roomId
            && $1.sessionId == sessionId
            && $1.algorithm == algorithm
            && $1.senderKey == senderKey
        }.values)
    }

    public func store(_ request: MXOutgoingRoomKeyRequest!) {
        outgoingRoomKeyRequests[request.requestId] = request
    }

    public func update(_ request: MXOutgoingRoomKeyRequest!) {
        outgoingRoomKeyRequests[request.requestId] = request
    }

    public func deleteOutgoingRoomKeyRequest(withRequestId requestId: String!) {
        outgoingRoomKeyRequests.removeValue(forKey: requestId)
    }

    // MARK: - Incoming Room Key Requests

    public func store(_ request: MXIncomingRoomKeyRequest!) {
        incomingRoomKeyRequestsMap[request.requestId] = request
    }

    public func deleteIncomingRoomKeyRequest(_ requestId: String!, fromUser userId: String!, andDevice deviceId: String!) {
        let toBeRemoved = incomingRoomKeyRequestsMap.filter { $1.requestId == requestId && $1.userId == userId && $1.deviceId == deviceId }
        for identifier in toBeRemoved {
            incomingRoomKeyRequestsMap.removeValue(forKey: identifier.key)
        }
    }

    public func incomingRoomKeyRequest(withRequestId requestId: String!, fromUser userId: String!, andDevice deviceId: String!) -> MXIncomingRoomKeyRequest! {
        incomingRoomKeyRequestsMap.first(where: { $1.requestId == requestId && $1.userId == userId && $1.deviceId == deviceId })?.value
    }

    public func incomingRoomKeyRequests() -> MXUsersDevicesMap<NSArray>! {
        let result = MXUsersDevicesMap<NSMutableArray>()

        for request in incomingRoomKeyRequestsMap {
            if let requests = result.object(forDevice: request.value.deviceId, forUser: request.value.userId) {
                requests.add(request.value)
            } else {
                let requests = NSMutableArray(object: request.value)
                result.setObject(requests, forUser: request.value.userId, andDevice: request.value.deviceId)
            }
        }

        return result as? MXUsersDevicesMap<NSArray>
    }

    // MARK: - Secrets

    public func storeSecret(_ secret: String, withSecretId secretId: String) {
        secrets[secretId] = secret
    }
    
    public func hasSecret(withSecretId secretId: String) -> Bool {
        return secrets[secretId] != nil
    }

    public func secret(withSecretId secretId: String) -> String? {
        secrets[secretId]
    }

    public func deleteSecret(withSecretId secretId: String) {
        secrets.removeValue(forKey: secretId)
    }

    // MARK: - Blacklist Unverified Devices

    public var globalBlacklistUnverifiedDevices: Bool {
        get {
            storeAccount?.globalBlacklistUnverifiedDevices ?? false
        } set {
            storeAccount?.globalBlacklistUnverifiedDevices = newValue
        }
    }

    public func blacklistUnverifiedDevices(inRoom roomId: String!) -> Bool {
        algorithms[roomId]?.blacklistUnverifiedDevices ?? false
    }

    public func storeBlacklistUnverifiedDevices(inRoom roomId: String!, blacklist: Bool) {
        if let algorithm = algorithms[roomId] {
            algorithm.blacklistUnverifiedDevices = blacklist
        } else {
            algorithms[roomId] = RoomAlgorithm(algorithm: nil, blacklistUnverifiedDevices: blacklist)
        }
    }

    // MARK: - Crypto Version

    public var cryptoVersion: MXCryptoVersion {
        get {
            storeAccount?.cryptoVersion ?? .versionUndefined
        } set {
            storeAccount?.cryptoVersion = newValue
        }
    }

}

// MARK: - Models

// MARK: InboundSession

private class InboundSession {
    let session: MXOlmInboundGroupSession
    var backedUp: Bool

    var sessionId: String {
        session.session.sessionIdentifier()
    }

    init(session: MXOlmInboundGroupSession,
         backedUp: Bool = false) {
        self.session = session
        self.backedUp = backedUp
    }
}

// MARK: OlmSessionMapKey

private struct OlmSessionMapKey: Hashable {
    let sessionId: String
    let deviceKey: String
}

// MARK: Account

private struct Account {
    var userId: String?
    var deviceId: String?
    var cryptoVersion: MXCryptoVersion = .versionUndefined
    var deviceSyncToken: String?
    var olmAccount: OLMAccount?
    var backupVersion: String?
    var globalBlacklistUnverifiedDevices: Bool = false
    var deviceTrackingStatus: [String : NSNumber]?
}

// MARK: SharedOutboundSession

private struct SharedOutboundSession {
    let roomId: String
    let sessionId: String
    let device: MXDeviceInfo
    let messageIndex: UInt
}

// MARK: RoomAlgorithm

private class RoomAlgorithm {
    let algorithm: String?
    var blacklistUnverifiedDevices: Bool

    init(algorithm: String?,
         blacklistUnverifiedDevices: Bool = false) {
        self.algorithm = algorithm
        self.blacklistUnverifiedDevices = blacklistUnverifiedDevices
    }
}

// 
// Copyright 2023 The Matrix.org Foundation C.I.C
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

import MatrixSDKCrypto

/// Object responsible for encrypting room events and ensuring that room keys are distributed to room members
protocol MXRoomEventEncrypting {
    
    /// Check if a particular room is encrypted
    func isRoomEncrypted(roomId: String) -> Bool
    
    /// Ensure that room keys have been shared with all eligible members
    func ensureRoomKeysShared(roomId: String) async throws
    
    /// Encrypt event content and return encrypted data
    func encrypt(
        content: [AnyHashable: Any],
        eventType: String,
        in room: MXRoom
    ) async throws -> [AnyHashable: Any]
    
    /// Respond to `m.room.encryption` event that may be setting a room encryption algorithm
    func handleRoomEncryptionEvent(_ event: MXEvent) async throws
}

struct MXRoomEventEncryption: MXRoomEventEncrypting {
    enum Error: Swift.Error {
        case missingRoom
        case invalidEncryptionAlgorithm
    }
    
    private static let keyRotationPeriodMsgs: Int = 100 // Rotate room keys after each 100 messages
    private static let keyRotationPeriodSec: Int = 7 * 24 * 3600 // Rotate room keys each week
    
    private let handler: MXCryptoRoomEventEncrypting
    private let legacyStore: MXCryptoStore
    private let getRoomAction: GetRoomAction
    private let log = MXNamedLog(name: "MXRoomEventEncryption")
    
    init(
        handler: MXCryptoRoomEventEncrypting,
        legacyStore: MXCryptoStore,
        getRoomAction: @escaping GetRoomAction
    ) {
        self.handler = handler
        self.legacyStore = legacyStore
        self.getRoomAction = getRoomAction
    }
    
    func isRoomEncrypted(roomId: String) -> Bool {
        // State of room encryption is not yet implemented in `MatrixSDKCrypto`
        // Will be moved to `MatrixSDKCrypto` eventually
        return legacyStore.algorithm(forRoom: roomId) != nil
    }
    
    func ensureRoomKeysShared(roomId: String) async throws {
        let room = try room(for: roomId)
        guard room.summary?.isEncrypted == true else {
            log.debug("Room is not encrypted")
            return
        }
        
        try await ensureEncryptionAndRoomKeys(in: room)
    }
    
    func encrypt(
        content: [AnyHashable: Any],
        eventType: String,
        in room: MXRoom
    ) async throws -> [AnyHashable: Any] {
        
        try await ensureEncryptionAndRoomKeys(in: room)
        
        let roomId = try roomId(for: room)
        return try handler.encryptRoomEvent(
            content: content,
            roomId: roomId,
            eventType: eventType
        )
    }
    
    func handleRoomEncryptionEvent(_ event: MXEvent) async throws {
        guard let roomId = event.roomId else {
            return
        }
        
        let room = try room(for: roomId)
        let state = try await room.state()
        try ensureRoomEncryption(roomId: roomId, algorithm: state.encryptionAlgorithm)
        
        let users = try await encryptionEligibleUsers(
            for: room,
            historyVisibility: state.historyVisibility
        )
        handler.addTrackedUsers(users)
    }
    
    // MARK: - Private
    
    /// Make sure we have adequately set the encryption algorithm for this room
    /// and shared our current room key with all its members
    private func ensureEncryptionAndRoomKeys(in room: MXRoom) async throws {
        guard let roomId = room.roomId else {
            throw Error.missingRoom
        }
        
        let state = try await room.state()
        try ensureRoomEncryption(roomId: roomId, algorithm: state.encryptionAlgorithm)
        
        let users = try await encryptionEligibleUsers(
            for: room,
            historyVisibility: state.historyVisibility
        )
        log.debug("Collected \(users.count) eligible users")
        
        let settings = try encryptionSettings(for: state)
        try await handler.shareRoomKeysIfNecessary(
            roomId: roomId,
            users: users,
            settings: settings
        )
        
        log.debug("Encryption and room keys up to date")
    }
    
    /// Make sure that we recognize (and store if necessary) the claimed room encryption algorithm
    private func ensureRoomEncryption(roomId: String, algorithm: String?) throws {
        let existingAlgorithm = legacyStore.algorithm(forRoom: roomId)
        if existingAlgorithm != nil && existingAlgorithm == algorithm {
            log.debug("Encryption in room is already set to the correct algorithm")
            return
        }
        
        guard let algorithm = algorithm else {
            log.error("Resetting encryption is not allowed")
            throw Error.invalidEncryptionAlgorithm
        }
        
        let supportedAlgorithms = Set([kMXCryptoMegolmAlgorithm])
        guard supportedAlgorithms.contains(algorithm) else {
            log.error("Ignoring invalid room algorithm", context: [
                "room_id": roomId,
                "algorithm": algorithm
            ])
            throw Error.invalidEncryptionAlgorithm
        }
        
        if let existing = existingAlgorithm, existing != algorithm {
            log.warning("New m.room.encryption event in \(roomId) with an algorithm change from \(existing) to \(algorithm)")
        } else {
            log.debug("New m.room.encryption event with algorithm \(algorithm)")
        }
        
        legacyStore.storeAlgorithm(forRoom: roomId, algorithm: algorithm)
    }
    
    /// Get user ids for all room members that should be able to decrypt events, based on the history visibility setting
    private func encryptionEligibleUsers(
        for room: MXRoom,
        historyVisibility: MXRoomHistoryVisibility?
    ) async throws -> [String] {
        guard
            let members = try await room.members(),
            let targetMembers = members.encryptionTargetMembers(historyVisibility?.identifier)
        else {
            log.error("Failed to get eligible users")
            return []
        }
        return targetMembers.compactMap(\.userId)
    }
    
    private func encryptionSettings(for state: MXRoomState) throws -> EncryptionSettings {
        guard let roomId = state.roomId else {
            throw Error.missingRoom
        }
        
        return .init(
            algorithm: .megolmV1AesSha2,
            rotationPeriod: UInt64(Self.keyRotationPeriodSec),
            rotationPeriodMsgs: UInt64(Self.keyRotationPeriodMsgs),
            // If not set, history visibility defaults to `joined` as the most restrictive setting
            historyVisibility: state.historyVisibility?.visibility ?? .joined,
            onlyAllowTrustedDevices: onlyTrustedDevices(in: roomId)
        )
    }
    
    private func onlyTrustedDevices(in roomId: String) -> Bool {
        return legacyStore.globalBlacklistUnverifiedDevices || legacyStore.blacklistUnverifiedDevices(inRoom: roomId)
    }
    
    private func room(for roomId: String) throws -> MXRoom {
        guard let room = getRoomAction(roomId) else {
            throw Error.missingRoom
        }
        return room
    }
    
    private func roomId(for room: MXRoom) throws -> String {
        guard let roomId = room.roomId else {
            throw Error.missingRoom
        }
        return roomId
    }
}

#endif

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
    private let getRoomAction: GetRoomAction
    private let log = MXNamedLog(name: "MXRoomEventEncryption")
    
    init(
        handler: MXCryptoRoomEventEncrypting,
        getRoomAction: @escaping GetRoomAction
    ) {
        self.handler = handler
        self.getRoomAction = getRoomAction
    }
    
    func isRoomEncrypted(roomId: String) -> Bool {
        return handler.roomSettings(roomId: roomId)?.algorithm != nil
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
        log.debug("Encrypting content of type `\(eventType)`")
        
        try await ensureEncryptionAndRoomKeys(in: room)
        log.debug("Encryption and room keys ensured")
        
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
        handler.updateTrackedUsers(users)
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
        
        // Room membership events should ensure that we are always tracking users as soon as possible,
        // but there are rare edge-cases where this does not always happen. To add a safety mechanism
        // we will always update tracked users when sharing keys (which does nothing if a user is
        // already tracked), triggering a key request for missing users in the next sync loop.
        handler.updateTrackedUsers(users)
        
        let settings = try encryptionSettings(for: state)
        try await handler.shareRoomKeysIfNecessary(
            roomId: roomId,
            users: users,
            settings: settings
        )
    }
    
    /// Make sure that we recognize (and store if necessary) the claimed room encryption algorithm
    private func ensureRoomEncryption(roomId: String, algorithm: String?) throws {
        log.debug("Attempting to set algorithm to \(algorithm ?? "empty")")
        
        do {
            let algorithm = try EventEncryptionAlgorithm(string: algorithm)
            try handler.setRoomAlgorithm(roomId: roomId, algorithm: algorithm)
        } catch {
            if let existing = handler.roomSettings(roomId: roomId)?.algorithm {
                log.error("Failed to set algorithm, but another room algorithm already stored", context: [
                    "existing": existing,
                    "new": algorithm ?? "empty"
                ])
            } else {
                log.error("Failed to set algorithm", context: error)
                throw error
            }
        }
        
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
            onlyAllowTrustedDevices: onlyTrustedDevices(in: roomId),
            errorOnVerifiedUserProblem: false
        )
    }
    
    private func onlyTrustedDevices(in roomId: String) -> Bool {
        return handler.onlyAllowTrustedDevices || handler.roomSettings(roomId: roomId)?.onlyAllowTrustedDevices == true
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

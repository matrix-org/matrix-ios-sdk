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

@objc public protocol MXUnrequestedForwardedRoomKeyManagerDelegate: AnyObject {
    func downloadDeviceKeys(userId: String, completion: @escaping (MXUsersDevicesMap<MXDeviceInfo>) -> Void)
    func acceptRoomKey(keyInfo: MXRoomKeyInfo)
}

@objcMembers
public class MXUnrequestedForwardedRoomKeyManager: NSObject {
    private typealias RoomId = String
    private typealias UserId = String
    
    static let MaximumTimeInterval: TimeInterval = 10 * 60
    
    struct PendingKey {
        let info: MXRoomKeyInfo
        let date: Date
    }
    
    struct RoomInvite {
        let roomId: String
        let senderId: String
        let date: Date
    }
    
    public weak var delegate: MXUnrequestedForwardedRoomKeyManagerDelegate?
    
    private let dateProvider: MXDateProviding
    private var pendingKeys = [RoomId: [UserId: [PendingKey]]]()
    private var roomInvites = [RoomInvite]()
    
    override public init() {
        self.dateProvider = MXDateProvider()
    }
    
    init(dateProvider: MXDateProviding) {
        self.dateProvider = dateProvider
    }
    
    public func close() {
        pendingKeys = [:]
        roomInvites = []
    }
    
    public func addPendingKey(keyInfo: MXRoomKeyInfo, senderId: String, senderKey: String) {
        guard let delegate = delegate else {
            MXLog.error("[MXUnrequestedForwardedRoomKeyManager] addPendingKey: Delegate is not set")
            return
        }
        
        // If just invited by the user we may not yet have their keys locally
        delegate.downloadDeviceKeys(userId: senderId) { [weak self] keys in
            guard let self = self else { return }
            
            guard let userId = self.matchingUserId(in: keys, userId: senderId, identityKey: senderKey) else {
                MXLog.error("[MXUnrequestedForwardedRoomKeyManager] addPendingKey: senderId does not match the claimed senderKey")
                return
            }
            self.addPendingKey(keyInfo: keyInfo, confirmedSenderId: userId)
            self.processUnrequestedKeys()
        }
    }
    
    public func onRoomInvite(roomId: String, senderId: String) {
        roomInvites.append(
            .init(
                roomId: roomId,
                senderId: senderId,
                date: dateProvider.currentDate()
            )
        )
    }
    
    public func processUnrequestedKeys() {
        guard let delegate = delegate else {
            MXLog.error("[MXUnrequestedForwardedRoomKeyManager] processUnrequestedKeys: Delegate is not set")
            return
        }
        
        let now = dateProvider.currentDate()
        
        roomInvites.removeAll {
            !$0.date.isWithin(timeInterval: Self.MaximumTimeInterval, of: now)
        }
        
        for invite in roomInvites {
            guard let roomKeys = pendingKeys[invite.roomId] else {
                continue
            }
            
            for (senderId, keys) in roomKeys {
                if invite.senderId == senderId {
                    for key in keys {
                        guard key.date.isWithin(timeInterval: Self.MaximumTimeInterval, of: invite.date) else {
                            continue
                        }
                        delegate.acceptRoomKey(keyInfo: key.info)
                    }
                }
            }
            
            pendingKeys[invite.roomId] = nil
        }
    }
    
    // MARK: - Private
    
    private func matchingUserId(in deviceKeys: MXUsersDevicesMap<MXDeviceInfo>, userId: String, identityKey: String) -> String? {
        return deviceKeys
            .objects(forUser: userId)?
            .first { $0.identityKey == identityKey }
            .flatMap { $0.userId }
    }
    
    private func addPendingKey(keyInfo: MXRoomKeyInfo, confirmedSenderId: String) {
        if pendingKeys[keyInfo.roomId] == nil {
            pendingKeys[keyInfo.roomId] = [:]
        }
        
        if pendingKeys[keyInfo.roomId]![confirmedSenderId] == nil {
            pendingKeys[keyInfo.roomId]![confirmedSenderId] = []
        }
        
        pendingKeys[keyInfo.roomId]![confirmedSenderId]!.append(
            .init(
                info: keyInfo,
                date: dateProvider.currentDate()
            )
        )
    }
}

private extension Date {
    func isWithin(timeInterval: TimeInterval, of date: Date) -> Bool {
        return abs(self.timeIntervalSince(date)) < timeInterval
    }
}

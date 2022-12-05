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

/// Payload sent via `PUT /sendToDevice` endpoint
@objcMembers public class MXToDevicePayload: NSObject {
    
    public let eventType: String
    public let transactionId: String
    public let messages: [String: [String: NSDictionary]]
    public let messageIds: [String]
    
    /// Initialize new to-device payload
    ///
    /// - Parameters:
    ///   - eventType: The type of event to send
    ///   - contentMap: Content to send. Map from user_id to device_id to content dictionary.
    ///   - transactionId: The transaction id to use. If nil, one will be generated.
    ///   - addMessageId: Whether to automatically generate new message id for each user/device.
    ///                   This is used for tracing messages across different systems
    public init(
        eventType: String,
        contentMap: MXUsersDevicesMap<NSDictionary>,
        transactionId: String?,
        addMessageId: Bool
    ) {
        self.eventType = eventType
        self.transactionId = transactionId ?? MXTools.generateTransactionId()
        
        var ids = [String]()
        if addMessageId {
            for (userId, devices) in contentMap.map {
                for (deviceId, content) in devices {
                    
                    let messageId = UUID().uuidString
                    let dict = NSMutableDictionary(dictionary: content)
                    dict[kMXToDeviceMessageId] = messageId
                    contentMap.setObject(
                        NSDictionary(dictionary: dict),
                        forUser: userId,
                        andDevice: deviceId
                    )
                    
                    ids.append("\(userId)/\(deviceId) \(messageId)")
                }
            }
        }
        
        self.messages = contentMap.map
        self.messageIds = ids
        
        super.init()
        
        MXLog.debug("[MXToDevicePayload] Created to-device payload with txnId \(self.transactionId), message ids: [\(self.messageIds.joined(separator: ", "))]")
    }
    
    convenience public init(
        eventType: String,
        contentMap: MXUsersDevicesMap<NSDictionary>
    ) {
        self.init(eventType: eventType, contentMap: contentMap, transactionId: nil, addMessageId: true)
    }
}

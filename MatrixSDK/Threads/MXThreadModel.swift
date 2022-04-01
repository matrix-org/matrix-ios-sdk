// 
// Copyright 2021 The Matrix.org Foundation C.I.C
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

@objcMembers
public class MXThreadModel: NSObject, MXThreadProtocol {

    public let id: String

    public let roomId: String

    public let notificationCount: UInt

    public let highlightCount: UInt

    public let isParticipated: Bool

    public private(set) var rootMessage: MXEvent?

    public private(set) var lastMessage: MXEvent?

    public private(set) var numberOfReplies: Int

    public init(withRootEvent rootEvent: MXEvent,
                notificationCount: UInt = 0,
                highlightCount: UInt = 0) {
        self.id = rootEvent.eventId
        self.roomId = rootEvent.roomId
        self.notificationCount = notificationCount
        self.highlightCount = highlightCount
        self.rootMessage = rootEvent
        if let thread = rootEvent.unsignedData?.relations?.thread {
            self.lastMessage = thread.latestEvent
            isParticipated = thread.hasParticipated
            numberOfReplies = Int(thread.numberOfReplies)
        } else {
            self.lastMessage = nil
            isParticipated = false
            numberOfReplies = 0
        }
        super.init()
    }

    internal func updateRootMessage(_ rootMessage: MXEvent) {
        self.rootMessage = rootMessage
    }

    internal func updateLastMessage(_ lastMessage: MXEvent) {
        self.lastMessage = lastMessage
    }

    internal func updateNumberOfReplies(_ numberOfReplies: Int) {
        self.numberOfReplies = numberOfReplies
    }

}

//  MARK: - Comparable

extension MXThreadModel: Comparable {

    /// Comparator for thread instances, to compare two threads according to their last message time.
    /// - Parameters:
    ///   - lhs: left operand
    ///   - rhs: right operand
    /// - Returns: true if left operand's last message is newer than the right operand's last message, false otherwise
    public static func < (lhs: MXThreadModel, rhs: MXThreadModel) -> Bool {
        //  thread will be 'smaller' than an other thread if it's last message is newer
        let leftLastMessage = lhs.lastMessage
        let rightLastMessage = rhs.lastMessage
        if let leftLastMessage = leftLastMessage {
            if let rightLastMessage = rightLastMessage {
                return leftLastMessage < rightLastMessage
            } else {
                return true
            }
        } else if rightLastMessage != nil {
            return false
        } else {
            return false
        }
    }

}

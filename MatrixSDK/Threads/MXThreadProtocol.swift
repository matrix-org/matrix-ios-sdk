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

@objc
public protocol MXThreadProtocol {

    /// Identifier of a thread. It's equal to identifier of the root event
    var id: String { get }

    /// Identifier of the room that the thread is in
    var roomId: String { get }

    /// Number of notifications in the thread
    var notificationCount: UInt { get }

    /// Number of highlights in the thread
    var highlightCount: UInt { get }

    /// Flag indicating the current user participated in the thread
    var isParticipated: Bool { get }

    /// Root message of the thread
    var rootMessage: MXEvent? { get }

    /// Last message of the thread
    var lastMessage: MXEvent? { get }

    /// Number of replies in the thread. Does not count the root event
    var numberOfReplies: Int { get }
}

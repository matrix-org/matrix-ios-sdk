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
public class MXThreadNotificationsCount: NSObject {
    
    /// Number of notified threads in a specific room
    public let numberOfNotifiedThreads: UInt
    
    /// Number of highlighted threads in a specific room
    public let numberOfHighlightedThreads: UInt
    
    /// Number of notifications in threads in a specific room
    public let notificationsNumber: UInt

    /// Initializer
    /// - Parameters:
    ///   - numberOfNotifiedThreads: number of notified threads
    ///   - numberOfHighlightedThreads: number of highlighted threads
    public init(numberOfNotifiedThreads: UInt,
                numberOfHighlightedThreads: UInt,
                notificationsNumber: UInt) {
        self.numberOfNotifiedThreads = numberOfNotifiedThreads
        self.numberOfHighlightedThreads = numberOfHighlightedThreads
        self.notificationsNumber = notificationsNumber
        super.init()
    }
    
}

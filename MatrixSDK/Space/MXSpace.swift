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

/// A Matrix space enables to collect rooms together into groups. Such collections of rooms are referred as "spaces" (see https://github.com/matrix-org/matrix-doc/blob/matthew/msc1772/proposals/1772-groups-as-rooms.md).
public class MXSpace: NSObject {
    
    // MARK: - Properties
    
    /// The underlying room
    public let room: MXRoom
    
    /// Shortcut to the room summary
    public var summary: MXRoomSummary? {
        return self.room.summary
    }
    
    // MARK: - Setup
    
    init(room: MXRoom) {
        self.room = room
        super.init()
    }
}

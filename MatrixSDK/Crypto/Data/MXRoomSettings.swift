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

// Object containing stored room settings, such as algorithm used
// and additional crypto options
@objc public class MXRoomSettings: NSObject {
    enum Error: Swift.Error {
        case missingParameters
    }
    
    public let roomId: String
    public let algorithm: String
    public let blacklistUnverifiedDevices: Bool
    
    @objc public init(
        roomId: String!,
        algorithm: String!,
        blacklistUnverifiedDevices: Bool
    ) throws {
        guard
            let roomId = roomId,
            let algorithm = algorithm
        else {
            throw Error.missingParameters
        }
        
        self.roomId = roomId
        self.algorithm = algorithm
        self.blacklistUnverifiedDevices = blacklistUnverifiedDevices
    }
}

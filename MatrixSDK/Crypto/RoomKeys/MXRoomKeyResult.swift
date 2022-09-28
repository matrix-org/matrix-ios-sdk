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

@objc public enum MXRoomKeyType: Int {
    case safe
    case unsafe
    case unrequested
}

@objcMembers
public class MXRoomKeyResult: NSObject {
    public let type: MXRoomKeyType
    public let info: MXRoomKeyInfo
    
    public init(type: MXRoomKeyType, info: MXRoomKeyInfo) {
        self.type = type
        self.info = info
    }
}

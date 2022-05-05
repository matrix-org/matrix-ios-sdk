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

/// MXEventAssetTypeMapper enables to get the corresponding MXEventAssetType from event key String and the other way around.
@objcMembers
public class MXEventAssetTypeMapper: NSObject {
    
    // MARK: - Public
    
    /// Return event key String associate to the MXEventAssetType given
    public func eventKey(from eventAssetType: MXEventAssetType) -> String {
        let eventKey: String
        switch eventAssetType {
        case .user:
            eventKey = kMXMessageContentKeyExtensibleAssetTypeUser
        case .pin:
            eventKey = kMXMessageContentKeyExtensibleAssetTypePin
        case .generic:
            eventKey = ""        
        @unknown default:
            eventKey = ""
        }
        return eventKey
    }
    
    /// Return MXEventAssetType associate to the event key String given
    public func eventAssetType(from eventKey: String) -> MXEventAssetType {
        let eventAssetType: MXEventAssetType
        switch eventKey {
        case kMXMessageContentKeyExtensibleAssetTypeUser:
            eventAssetType = .user
        case kMXMessageContentKeyExtensibleAssetTypePin:
            eventAssetType = .pin
        default:
            eventAssetType = .generic
        }
        return eventAssetType
    }
}

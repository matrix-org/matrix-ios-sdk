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

/// Status of capability for a room version
public enum MXRoomVersionStatus: String {
    /// the feature is supported by a stable version
    case stable = "stable"
    /// the feature is supported by an unstable version (should only be used for dev/experimental purpose).
    case unstable = "unstable"
}

/// All types of features (e.g. room capabilities)
public enum MXRoomCapabilityStringType: String {
    /// knocking join rule support [MSC2403](https://github.com/matrix-org/matrix-doc/pull/2403)
    case knock = "knock"
    /// restricted join rule support [MSC3083](https://github.com/matrix-org/matrix-doc/pull/3083)
    case restricted = "restricted"
}

/// All types of features (objective-C support)
@objc public enum MXRoomCapabilityType: Int {
    /// knocking join rule support [MSC2403](https://github.com/matrix-org/matrix-doc/pull/2403)
    case knock
    /// restricted join rule support [MSC3083](https://github.com/matrix-org/matrix-doc/pull/3083)
    case restricted
}

/// MXRoomCapabilityTypeMapper enables to get the corresponding room capability type from a room capability type string and the other way around.
@objcMembers
public class MXRoomCapabilityTypeMapper: NSObject {
    
    // MARK: - Public
    
    public func roomCapabilityType(from roomCapabilityTypeString: String) -> MXRoomCapabilityType? {
        let roomCapabilityType: MXRoomCapabilityType?
        
        switch roomCapabilityTypeString {
        case MXRoomCapabilityStringType.knock.rawValue:
            roomCapabilityType = .knock
        case MXRoomCapabilityStringType.restricted.rawValue:
            roomCapabilityType = .restricted
        default:
            roomCapabilityType = nil
        }
        
        return roomCapabilityType
    }
    
    public func roomCapabilityStringType(from roomCapabilityType: MXRoomCapabilityType) -> MXRoomCapabilityStringType? {
        switch roomCapabilityType {
        case .knock: return .knock
        case .restricted: return .restricted
        default: return nil
        }
    }
    
}

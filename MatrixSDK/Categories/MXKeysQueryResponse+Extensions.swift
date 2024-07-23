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


extension MXKeysQueryResponse : MXSummable {
    
    public static func +(lhs: MXKeysQueryResponse, rhs: MXKeysQueryResponse) -> Self {
        let keysQueryResponse = MXKeysQueryResponse()
        
        // Casts to original objc NSDictionary are annoying
        // but we want to reuse our implementation of NSDictionary.+
        let deviceKeysMap = (lhs.deviceKeys?.map as NSDictionary? ?? NSDictionary())
            + (rhs.deviceKeys?.map as NSDictionary? ?? NSDictionary())
        keysQueryResponse.deviceKeys = MXUsersDevicesMap<MXDeviceInfo>(map: deviceKeysMap as? [String: [String: MXDeviceInfo]])
        
        let crossSigningKeys = (lhs.crossSigningKeys as NSDictionary? ?? NSDictionary())
            + (rhs.crossSigningKeys as NSDictionary? ?? NSDictionary())
        keysQueryResponse.crossSigningKeys = crossSigningKeys as? [String: MXCrossSigningInfo]
        
        let failures = (lhs.failures as NSDictionary? ?? NSDictionary())
            + (rhs.failures as NSDictionary? ?? NSDictionary())
        keysQueryResponse.failures = failures as? [AnyHashable : Any]
        
        return keysQueryResponse as! Self
    }
}


extension MXKeysQueryResponseRaw : MXSummable {
    
    public static func +(lhs: MXKeysQueryResponseRaw, rhs: MXKeysQueryResponseRaw) -> Self {
        let keysQueryResponse = MXKeysQueryResponseRaw()
        
        // Casts to original objc NSDictionary are annoying
        // but we want to reuse our implementation of NSDictionary.+
        let deviceKeysMap = (lhs.deviceKeys as NSDictionary? ?? NSDictionary())
        + (rhs.deviceKeys as NSDictionary? ?? NSDictionary())
        keysQueryResponse.deviceKeys = deviceKeysMap as? [String : Any]
        
        let crossSigningKeys = (lhs.crossSigningKeys as NSDictionary? ?? NSDictionary())
            + (rhs.crossSigningKeys as NSDictionary? ?? NSDictionary())
        keysQueryResponse.crossSigningKeys = crossSigningKeys as? [String: MXCrossSigningInfo]
        
        let failures = (lhs.failures as NSDictionary? ?? NSDictionary())
            + (rhs.failures as NSDictionary? ?? NSDictionary())
        keysQueryResponse.failures = failures as? [AnyHashable : Any]
        
        return keysQueryResponse as! Self
    }
}

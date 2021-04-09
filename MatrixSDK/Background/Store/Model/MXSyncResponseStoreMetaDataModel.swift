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

struct MXSyncResponseStoreMetaDataModel {
    /// Store versions
    enum Versions: Int, Codable {
        case v1 = 1
    }
    
    /// Version of the store
    var version: Versions = .v1
    
    /// User account data
    var accountData: [String : Any]?
    
    /// All valid cached sync responses, chronologically ordered
    var syncResponseIds: [String] = []
    
    /// All obsolote cached sync responses, chronologically ordered
    var outdatedSyncResponseIds: [String] = []
}


extension MXSyncResponseStoreMetaDataModel: Codable {
    enum CodingKeys: String, CodingKey {
        case version
        case accountData
        case syncResponseIds
        case outdatedSyncResponseIds
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        version = try values.decode(Versions.self, forKey: .version)
        if let data = try values.decodeIfPresent(Data.self, forKey: .accountData) {
            accountData =  try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        }
        syncResponseIds = try values.decode([String].self, forKey: .syncResponseIds)
        outdatedSyncResponseIds = try values.decode([String].self, forKey: .outdatedSyncResponseIds)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(version, forKey: .version)
        if let accountData = accountData {
            let data = try JSONSerialization.data(withJSONObject: accountData)
            try container.encodeIfPresent(data, forKey: .accountData)
        }
        try container.encode(syncResponseIds, forKey: .syncResponseIds)
        try container.encode(outdatedSyncResponseIds, forKey: .outdatedSyncResponseIds)
    }
}

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
    var accountData: [AnyHashable : Any]? = nil
}


extension MXSyncResponseStoreMetaDataModel: Codable {
    enum CodingKeys: String, CodingKey {
        case accountData
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        if let data = try values.decodeIfPresent(Data.self, forKey: .accountData) {
            accountData =  try JSONSerialization.jsonObject(with: data, options: []) as? [AnyHashable: Any]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let accountData = accountData {
            let data = try JSONSerialization.data(withJSONObject: accountData)
            try container.encodeIfPresent(data, forKey: .accountData)
        }
    }
}

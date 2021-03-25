// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

/// Protocol defining the storage for a sync response.
@objc public protocol MXSyncResponseStore: NSObjectProtocol {
    /// Open the store with the given credentials
    /// - Parameter credentials: Credentials
    func open(withCredentials credentials: MXCredentials)
    
    /// Cached sync response
    var syncResponse: MXCachedSyncResponse? { get set }
    
    /// User account data
    var accountData: [AnyHashable : Any]? { get set }
    
    /// Delete all data in the store
    func deleteData()
}

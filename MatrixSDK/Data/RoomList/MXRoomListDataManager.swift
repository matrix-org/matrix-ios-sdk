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

@objc
/// Room list data manager interface
public protocol MXRoomListDataManager {
    
    /// Configured session
    var session: MXSession? { get }
    
    /// Configures the data manager with a session. It's only valid for the first time.
    /// - Parameter session: session to configure with
    func configure(withSession session: MXSession)
    
    /// Creates a fetcher object. Manager implementation should not keep a strong reference to this fetcher. It should be caller's responsibility.
    /// - Parameter options: fetch options for the fetcher
    func fetcher(withOptions options: MXRoomListDataFetchOptions) -> MXRoomListDataFetcher
}

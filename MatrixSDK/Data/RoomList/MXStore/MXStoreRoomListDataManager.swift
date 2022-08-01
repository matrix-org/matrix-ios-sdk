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

@objcMembers
public class MXStoreRoomListDataManager: NSObject, MXRoomListDataManager {
    public weak var session: MXSession?
    
    public func configure(withSession session: MXSession) {
        assert(self.session == nil, "[MXStoreRoomListDataManager] Cannot configure the session again")
        self.session = session
    }
    
    public func fetcher(withOptions options: MXRoomListDataFetchOptions) -> MXRoomListDataFetcher {
        if options.filterOptions.onlySuggested {
            guard let session = session, let spaceService = session.spaceService else {
                fatalError("[MXStoreRoomListDataManager] Session has no spaceService")
            }
            return MXSuggestedRoomListDataFetcher(fetchOptions: options,
                                                  session: session,
                                                  spaceService: spaceService)
        }
        if options.filterOptions.onlyBreadcrumbs {
            return MXBreadcrumbsRoomListDataFetcher(fetchOptions: options, session: session)
        }
        guard let store = session?.store else {
            fatalError("[MXStoreRoomListDataManager] Session has no store")
        }
        return MXStoreRoomListDataFetcher(fetchOptions: options,
                                          store: store.roomSummaryStore)
    }
}

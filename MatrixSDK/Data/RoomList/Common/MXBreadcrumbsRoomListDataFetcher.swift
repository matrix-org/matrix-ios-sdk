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

@objcMembers
internal class MXBreadcrumbsRoomListDataFetcher: NSObject, MXRoomListDataFetcher {
    internal var fetchOptions: MXRoomListDataFetchOptions
    private weak var session: MXSession?
    private var recentsRooms: [String] = []
    
    private var allRoomSummaries: [MXRoomSummaryProtocol] = []
    private var sessionSyncObserver: Any?
    
    private var recentRoomIds: [String] = []

    private let multicastDelegate: MXMulticastDelegate<MXRoomListDataFetcherDelegate> = MXMulticastDelegate()

    var data: MXRoomListData? {
        didSet {
            guard data != nil else {
                //  do not notify when stopped
                return
            }
            
            notifyDataChange()
        }
    }
    
    internal init(fetchOptions: MXRoomListDataFetchOptions,
                  session: MXSession?) {
        self.fetchOptions = fetchOptions
        self.session = session
        super.init()
        self.fetchOptions.fetcher = self
        self.refresh()
        self.addDataObservers()
    }

    //  MARK: - Delegate
    
    func addDelegate(_ delegate: MXRoomListDataFetcherDelegate) {
        multicastDelegate.addDelegate(delegate)
    }
    
    func removeDelegate(_ delegate: MXRoomListDataFetcherDelegate) {
        multicastDelegate.removeDelegate(delegate)
    }
    
    func removeAllDelegates() {
        multicastDelegate.removeAllDelegates()
    }
    
    internal func notifyDataChange() {
        multicastDelegate.invoke({ $0.fetcherDidChangeData(self, totalCountsChanged: true) })
    }

    func paginate() {
        // Do nothing. We don't paginate breadcrumbs
    }
    
    func resetPagination() {
        // Do nothing. We don't paginate breadcrumbs
    }
    
    // MARK: - Public
    
    func refresh() {
        guard let breadcrumbs = session?.accountData?.accountData(forEventType: kMXAccountDataTypeBreadcrumbs) as? [AnyHashable: [String]] else {
            MXLog.warning("[MXBreadcrumbsRoomListDataFetcher] cannot retrieve breadcrumbs")
            return
        }
        
        guard var recentRoomIds = breadcrumbs[kMXAccountDataTypeRecentRoomsKey] else {
            MXLog.warning("[MXBreadcrumbsRoomListDataFetcher] cannot retrieve recent rooms")
            return
        }
        
        if let query = fetchOptions.filterOptions.query?.lowercased(), !query.isEmpty {
            recentRoomIds = recentRoomIds.filter({ roomId in
                guard let displayName = session?.roomSummary(withRoomId: roomId)?.displayName else {
                    return false
                }
                return displayName.lowercased().contains(query)
            })
        }
        
        guard self.recentRoomIds != recentRoomIds else {
            // Nothing to do then
            return
        }

        let summaries: [MXRoomSummary] = recentRoomIds.compactMap {
            guard let summary = session?.roomSummary(withRoomId: $0), summary.roomType == .room else {
                return nil
            }
            return summary
        }
        
        var total: MXRoomListDataCounts?
        if !summaries.isEmpty {
            //  compute total counts just before cutting the rooms array
            total = MXStoreRoomListDataCounts(withRooms: summaries, total: nil)
        }

        self.data = MXRoomListData(rooms: summaries,
                                   counts: MXStoreRoomListDataCounts(withRooms: summaries,
                                                                     total: total),
                                   paginationOptions: fetchOptions.paginationOptions)
        self.recentRoomIds = recentRoomIds
    }
    
    func stop() {
        removeAllDelegates()
        removeDataObservers()
        data = nil
        recentRoomIds = []
    }
    
    // MARK: - Data observers
    
    func addDataObservers() {
        sessionSyncObserver = NotificationCenter.default.addObserver(forName:NSNotification.Name.mxSessionAccountDataDidChangeBreadcrumbs, object:session, queue:OperationQueue.main) { [weak self] (_) in
            guard let self = self else { return }
            
            self.refresh()
        }
    }
    
    func removeDataObservers() {
        if let sessionSyncObserver = sessionSyncObserver {
            NotificationCenter.default.removeObserver(sessionSyncObserver)
        }
    }
    
}

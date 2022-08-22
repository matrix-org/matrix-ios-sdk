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
internal class MXSuggestedRoomListDataFetcher: NSObject, MXRoomListDataFetcher {
    
    internal let fetchOptions: MXRoomListDataFetchOptions
    private weak var session: MXSession?
    private let spaceService: MXSpaceService
    private let cache: MXSuggestedRoomListDataCache
    
    private var allRoomSummaries: [MXRoomSummaryProtocol] = []
    
    private let multicastDelegate: MXMulticastDelegate<MXRoomListDataFetcherDelegate> = MXMulticastDelegate()
    private var space: MXSpace? {
        didSet {
            if space != oldValue {
                removeDataObservers(for: oldValue)
                addDataObservers(for: space)
            }
        }
    }
    private var spaceEventsListener: Any?
    private var currentHttpOperation: MXHTTPOperation?
    private var sessionDidSyncObserver: Any?
    
    internal private(set) var data: MXRoomListData? {
        didSet {
            guard let data = data else {
                //  do not notify when stopped
                return
            }
            if data != oldValue {
                notifyDataChange()
            }
        }
    }
    
    internal init(fetchOptions: MXRoomListDataFetchOptions,
                  session: MXSession,
                  spaceService: MXSpaceService,
                  cache: MXSuggestedRoomListDataCache = .shared) {
        self.fetchOptions = fetchOptions
        self.session = session
        self.spaceService = spaceService
        self.cache = cache
        self.space = fetchOptions.filterOptions.space
        super.init()
        self.fetchOptions.fetcher = self
        addDataObservers(for: space)
    }
    
    //  MARK: - Delegate
    
    internal func addDelegate(_ delegate: MXRoomListDataFetcherDelegate) {
        multicastDelegate.addDelegate(delegate)
    }
    
    internal func removeDelegate(_ delegate: MXRoomListDataFetcherDelegate) {
        multicastDelegate.removeDelegate(delegate)
    }
    
    internal func removeAllDelegates() {
        multicastDelegate.removeAllDelegates()
    }
    
    internal func notifyDataChange() {
        multicastDelegate.invoke({ $0.fetcherDidChangeData(self, totalCountsChanged: true) })
    }
    
    //  MARK: - Data Observers
    
    private func addDataObservers(for space: MXSpace?) {
        spaceEventsListener = space?.room?.listen(toEvents: { [weak self] event, direction, roomState in
            guard let self = self else { return }
            if let space = self.space {
                //  clear cache for this space
                self.cache[space] = nil
            }
            self.refresh()
        })
        sessionDidSyncObserver = NotificationCenter.default.addObserver(forName: .mxSessionDidSync, object: nil, queue: OperationQueue.main) { [weak self] notification in
            self?.updateData()
        }
    }
    
    private func removeDataObservers(for space: MXSpace?) {
        space?.room?.removeListener(spaceEventsListener)
        if let observer = sessionDidSyncObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    internal func paginate() {
        let numberOfItems: Int
        
        if let data = data {
            //  load next page
            switch fetchOptions.paginationOptions {
            case .none:
                //  pagination disabled, so all rooms should be fetched in the first request
                return
            default:
                if data.counts.numberOfRooms % fetchOptions.paginationOptions.rawValue != 0 {
                    //  there is not a full page, so no more data
                    return
                }
                numberOfItems = (data.currentPage + 2) * data.paginationOptions.rawValue
            }
        } else {
            //  load first page
            numberOfItems = fetchOptions.paginationOptions.rawValue
        }
        
        computeData(upto: numberOfItems)
    }
    
    internal func resetPagination() {
        computeData(upto: fetchOptions.paginationOptions.rawValue)
    }
    
    internal func refresh() {
        //  cancel current request
        currentHttpOperation?.cancel()
        currentHttpOperation = nil
        space = fetchOptions.filterOptions.space
        if let oldData = data {
            data = nil
            recomputeData(using: oldData)
        } else {
            paginate()
        }
    }
    
    internal func stop() {
        removeAllDelegates()
        removeDataObservers(for: space)
        data = nil
    }
    
    //  MARK: - Private
    
    /// Recompute data with the same number of rooms of the given `data`
    private func recomputeData(using data: MXRoomListData) {
        let numberOfItems = (data.currentPage + 1) * data.paginationOptions.rawValue
        computeData(upto: numberOfItems)
    }
    
    private func computeData(upto numberOfItems: Int) {
        guard let space = space else {
            return
        }
        guard let summary = cache[space] else {
            //  no cache
            fetchSpaceChildren(upto: numberOfItems, space: space)
            return
        }
        
        //  cache exists
        if summary.childInfos.count >= numberOfItems {
            //  there are enough number of items in the cache
            computeData(from: summary.childInfos)
        } else {
            switch fetchOptions.paginationOptions {
            case .none:
                //  pagination disabled, so all rooms should be fetched in the first request
                computeData(from: summary.childInfos)
            default:
                guard summary.childInfos.count % fetchOptions.paginationOptions.rawValue == 0 else {
                    //  no more data to fetch, compute data as it is
                    computeData(from: summary.childInfos)
                    return
                }
                fetchSpaceChildren(upto: numberOfItems, space: space)
            }
        }
    }
    
    private func fetchSpaceChildren(upto numberOfItems: Int, space: MXSpace) {
        //  do the request
        //  limit should be -1 for no limit
        let limit: Int = numberOfItems < 0 ? -1 : numberOfItems
        currentHttpOperation =  spaceService.getSpaceChildrenForSpace(withId: space.spaceId, suggestedOnly: true, limit: limit, maxDepth: 1, paginationToken: nil) { [weak self] response in
            guard let self = self else { return }
            switch response {
            case .success(let summary):
                //  cache the data
                self.cache[space] = summary
                //  if we're still on the same space, advertise the data
                if self.space == space {
                    self.computeData(from: summary.childInfos)
                }
            case .failure(let error):
                MXLog.error("[MXSuggestedRoomListDataFetcher] fetchSpaceChildren failed", context: error)
            }
        }
    }
    
    private func computeData(from childInfos: [MXSpaceChildInfo]) {
        //  create room summary objects
        var rooms: [MXRoomSummaryProtocol] = childInfos.compactMap({ MXRoomSummary(spaceChildInfo: $0) })
        rooms = filterRooms(rooms)
        rooms = sortRooms(rooms)
        allRoomSummaries = rooms
        updateData()
    }
    
    private func updateData() {
        let summaries = allRoomSummaries.filter { summary in
            guard summary.spaceChildInfo?.roomType == .room else {
                return false
            }
            guard let room = self.session?.room(withRoomId: summary.roomId), let localsummary = room.summary else {
                return true
            }
            
            return localsummary.membership != .join && localsummary.membership != .invite && localsummary.membership != .ban
        }
        
        //  we don't know total rooms count, passing as current number of rooms
        self.data = MXRoomListData(rooms: summaries,
                                   counts: MXStoreRoomListDataCounts(withRooms: summaries,
                                                                     total: nil),
                                   paginationOptions: fetchOptions.paginationOptions)
    }
    
}

//  MARK: MXRoomListDataSortable

extension MXSuggestedRoomListDataFetcher: MXRoomListDataSortable {
    
    var sortOptions: MXRoomListDataSortOptions {
        return fetchOptions.sortOptions
    }
    
}

//  MARK: MXRoomListDataFilterable

extension MXSuggestedRoomListDataFetcher: MXRoomListDataFilterable {
    
    var filterOptions: MXRoomListDataFilterOptions {
        return fetchOptions.filterOptions
    }
    
}

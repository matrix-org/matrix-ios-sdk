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
    
    public let fetchOptions: MXRoomListDataFetchOptions
    private let spaceService: MXSpaceService
    private let cache: MXSuggestedRoomListDataCache
    
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
    
    public private(set) var data: MXRoomListData? {
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
                  spaceService: MXSpaceService,
                  cache: MXSuggestedRoomListDataCache = .shared) {
        self.fetchOptions = fetchOptions
        self.spaceService = spaceService
        self.cache = cache
        self.space = fetchOptions.filterOptions.space
        super.init()
        self.fetchOptions.fetcher = self
        addDataObservers(for: space)
    }
    
    //  MARK: - Delegate
    
    public func addDelegate(_ delegate: MXRoomListDataFetcherDelegate) {
        multicastDelegate.addDelegate(delegate)
    }
    
    public func removeDelegate(_ delegate: MXRoomListDataFetcherDelegate) {
        multicastDelegate.removeDelegate(delegate)
    }
    
    public func removeAllDelegates() {
        multicastDelegate.removeAllDelegates()
    }
    
    private func notifyDataChange() {
        multicastDelegate.invoke(invocation: { $0.fetcherDidChangeData(self) })
    }
    
    //  MARK: - Data Observers
    
    private func addDataObservers(for space: MXSpace?) {
        spaceEventsListener = space?.room.listen(toEvents: { [weak self] event, direction, roomState in
            guard let self = self else { return }
            self.refresh()
        })
    }
    
    private func removeDataObservers(for space: MXSpace?) {
        space?.room.removeListener(spaceEventsListener)
    }
    
    func paginate() {
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
    
    func resetPagination() {
        computeData(upto: fetchOptions.paginationOptions.rawValue)
    }
    
    func refresh() {
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
    
    func stop() {
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
        if let summary = cache[space] {
            //  cache exists
            if summary.childInfos.count >= numberOfItems {
                //  there are desired number of items in the cache
                computeData(from: summary.childInfos)
                return
            } else {
                
            }
        }
        //  do the request
        //  limit should be -1 for no limit
        let limit: Int = numberOfItems < 0 ? -1 : numberOfItems
        currentHttpOperation = spaceService.getSpaceChildrenForSpace(withId: space.spaceId,
                                                                     suggestedOnly: true,
                                                                     limit: limit) { [weak self] response in
            guard let self = self else { return }
            switch response {
            case .success(let summary):
                self.cache[space] = summary
                //  if we're still on the same space, advertise the data
                if self.space == space {
                    self.computeData(from: summary.childInfos)
                }
            case .failure(let error):
                MXLog.error("[MXSuggestedRoomListDataFetcher] computeData failed: \(error)")
            }
        }
    }
    
    private func computeData(from childInfos: [MXSpaceChildInfo]) {
        //  create room summary objects
        var rooms: [MXRoomSummaryProtocol] = childInfos.map({ MXRoomSummary(spaceChildInfo: $0) })
        rooms = fetchOptions.filterOptions.filterRooms(rooms)
        rooms = fetchOptions.sortOptions.sortRooms(rooms)
        //  we don't know total rooms count, passing as current number of rooms
        self.data = MXRoomListData(rooms: rooms,
                                   counts: MXStoreRoomListDataCounts(withRooms: rooms,
                                                                     totalRoomsCount: rooms.count),
                                   paginationOptions: fetchOptions.paginationOptions)
    }
    
}

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
internal class MXStoreRoomListDataFetcher: NSObject, MXRoomListDataFetcher {
    internal private(set) var data: MXRoomListData? {
        didSet {
            guard let data = data else {
                //  do not notify when stopped
                return
            }
            if data != oldValue {
                let totalCountsChanged: Bool
                if fetchOptions.paginationOptions == .none {
                    //  pagination disabled, we don't need to track number of rooms in this case
                    totalCountsChanged = true
                } else {
                    totalCountsChanged = oldValue?.counts.total?.numberOfRooms != data.counts.total?.numberOfRooms
                }
                notifyDataChange(totalCountsChanged: totalCountsChanged)
            }
        }
    }
    internal let fetchOptions: MXRoomListDataFetchOptions
    private let store: MXRoomSummaryStore
    
    private let multicastDelegate: MXMulticastDelegate<MXRoomListDataFetcherDelegate> = MXMulticastDelegate()
    private var roomSummaries: [String: MXRoomSummaryProtocol] = [:]
    private let executionQueue: DispatchQueue = DispatchQueue(label: "MXStoreRoomListDataFetcherQueue-" + MXTools.generateSecret())
    
    internal init(fetchOptions: MXRoomListDataFetchOptions,
                  store: MXRoomSummaryStore) {
        self.fetchOptions = fetchOptions
        self.store = store
        super.init()
        self.fetchOptions.fetcher = self
        addDataObservers()
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
    
    //  MARK: - Data
    
    internal func paginate() {
        if fetchOptions.async {
            executionQueue.async { [weak self] in
                guard let self = self else { return }
                self.innerPaginate()
            }
        } else {
            executionQueue.sync { [weak self] in
                guard let self = self else { return }
                self.innerPaginate()
            }
        }
    }
    
    internal func resetPagination() {
        if fetchOptions.async {
            executionQueue.async { [weak self] in
                guard let self = self else { return }
                self.innerResetPagination()
            }
        } else {
            executionQueue.sync { [weak self] in
                guard let self = self else { return }
                self.innerResetPagination()
            }
        }
    }
    
    internal func refresh() {
        guard let oldData = data else {
            return
        }
        data = nil
        recomputeData(using: oldData)
    }
    
    internal func stop() {
        removeAllDelegates()
        removeDataObservers()
        data = nil
    }
    
    //  MARK: - Private
    
    private func innerPaginate() {
        let numberOfItems: Int
        
        if let data = data {
            //  load next page
            guard data.hasMoreRooms else {
                //  there is no more rooms to paginate
                return
            }
            //  MXStore implementation does not provide any pagination options.
            //  We'll try to change total number of items we fetched when paginating further.
            //  Case: we've loaded our nth page of data with pagination size P.
            //  To further paginate, we'll try to fetch (n+2)*P items in total.
            numberOfItems = (data.currentPage + 2) * data.paginationOptions.rawValue
        } else {
            //  load first page
            for roomId in store.rooms {
                if let summary = store.summary(ofRoom: roomId) {
                    self.roomSummaries[roomId] = summary
                }
            }
            numberOfItems = fetchOptions.paginationOptions.rawValue
        }
        
        data = computeData(upto: numberOfItems)
    }
    
    /// Load first page again
    private func innerResetPagination() {
        data = computeData(upto: fetchOptions.paginationOptions.rawValue)
    }
    
    /// Recompute data with the same number of rooms of the given `data`
    private func recomputeData(using data: MXRoomListData) {
        let numberOfItems = (data.currentPage + 1) * data.paginationOptions.rawValue
        self.data = computeData(upto: numberOfItems)
    }
    
    /// Compute data up to a numberOfItems
    private func computeData(upto numberOfItems: Int) -> MXRoomListData {
        var rooms = Array(roomSummaries.values)
        rooms = filterRooms(rooms)
        rooms = sortRooms(rooms)
        
        var total: MXRoomListDataCounts?
        
        if numberOfItems > 0 && rooms.count > numberOfItems {
            //  compute total counts just before cutting the rooms array
            total = MXStoreRoomListDataCounts(withRooms: rooms, total: nil)
            rooms = Array(rooms[0..<numberOfItems])
        }
        
        return MXRoomListData(rooms: rooms,
                              counts: MXStoreRoomListDataCounts(withRooms: rooms,
                                                                total: total),
                              paginationOptions: fetchOptions.paginationOptions)
    }
    
    private func notifyDataChange(totalCountsChanged: Bool) {
        multicastDelegate.invoke({ $0.fetcherDidChangeData(self, totalCountsChanged: totalCountsChanged) })
    }
    
    //  MARK: - Data Observers
    
    private func addDataObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(roomAdded(_:)),
                                               name: .mxSessionNewRoom,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(roomRemoved(_:)),
                                               name: .mxSessionDidLeaveRoom,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(roomSummaryUpdated(_:)),
                                               name: .mxRoomSummaryDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(directRoomsUpdated(_:)),
                                               name: .mxSessionDirectRoomsDidChange,
                                               object: nil)
    }
    
    private func removeDataObservers() {
        NotificationCenter.default.removeObserver(self,
                                                  name: .mxSessionNewRoom,
                                                  object: nil)
        NotificationCenter.default.removeObserver(self,
                                                  name: .mxSessionDidLeaveRoom,
                                                  object: nil)
        NotificationCenter.default.removeObserver(self,
                                                  name: .mxRoomSummaryDidChange,
                                                  object: nil)
        NotificationCenter.default.removeObserver(self,
                                                  name: .mxSessionDirectRoomsDidChange,
                                                  object: nil)
    }
    
    @objc
    private func roomAdded(_ notification: Notification) {
        executionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let data = self.data else {
                //  ignore this change if we never computed data yet
                return
            }
            guard let roomId = notification.userInfo?[kMXSessionNotificationRoomIdKey] as? String else {
                return
            }
            guard let summary = self.store.summary(ofRoom: roomId) else {
                MXLog.error("[MXStoreRoomListDataManager] roomAdded: room not found in the store", context: [
                    "room_id": roomId
                ])
                return
            }
            self.roomSummaries[roomId] = summary
            self.recomputeData(using: data)
        }
    }
    
    @objc
    private func roomRemoved(_ notification: Notification) {
        executionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let data = self.data else {
                //  ignore this change if we never computed data yet
                return
            }
            guard let roomId = notification.userInfo?[kMXSessionNotificationRoomIdKey] as? String else {
                return
            }
            self.roomSummaries.removeValue(forKey: roomId)
            self.recomputeData(using: data)
        }
    }
    
    @objc
    private func roomSummaryUpdated(_ notification: Notification) {
        executionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let data = self.data else {
                //  ignore this change if we never computed data yet
                return
            }
            guard let summary = notification.object as? MXRoomSummary else {
                return
            }
            self.roomSummaries[summary.roomId] = summary
            self.recomputeData(using: data)
        }
    }
    
    @objc
    private func directRoomsUpdated(_ notification: Notification) {
        executionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let data = self.data else {
                //  ignore this change if we never computed data yet
                return
            }
            self.recomputeData(using: data)
        }
    }
    
    deinit {
        stop()
    }
    
}

//  MARK: MXRoomListDataSortable

extension MXStoreRoomListDataFetcher: MXRoomListDataSortable {
    
    var sortOptions: MXRoomListDataSortOptions {
        return fetchOptions.sortOptions
    }
    
}

//  MARK: MXRoomListDataFilterable

extension MXStoreRoomListDataFetcher: MXRoomListDataFilterable {
    
    var filterOptions: MXRoomListDataFilterOptions {
        return fetchOptions.filterOptions
    }
    
}

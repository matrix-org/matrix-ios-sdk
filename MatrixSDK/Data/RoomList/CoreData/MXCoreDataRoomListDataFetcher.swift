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
import CoreData

internal typealias MXRoomSummaryCoreDataContextableStore = MXRoomSummaryStore & CoreDataContextable

@objcMembers
internal class MXCoreDataRoomListDataFetcher: NSObject, MXRoomListDataFetcher {
    
    private let multicastDelegate: MXMulticastDelegate<MXRoomListDataFetcherDelegate> = MXMulticastDelegate()
    
    internal let fetchOptions: MXRoomListDataFetchOptions
    
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
    private let store: MXRoomSummaryCoreDataContextableStore
    
    private lazy var fetchedResultsController: NSFetchedResultsController<MXRoomSummaryModel> = {
        let request = MXRoomSummaryModel.typedFetchRequest()
        request.predicate = filterPredicate(for: filterOptions)
        request.sortDescriptors = sortDescriptors(for: sortOptions)
        request.fetchLimit = fetchOptions.paginationOptions.rawValue
        let controller = NSFetchedResultsController(fetchRequest: request,
                                                    managedObjectContext: store.managedObjectContext,
                                                    sectionNameKeyPath: nil,
                                                    cacheName: nil)
        controller.delegate = self
        return controller
    }()
    
    private var totalRoomsCount: Int {
        let request = MXRoomSummaryModel.typedFetchRequest()
        request.predicate = filterPredicate(for: filterOptions)
        request.resultType = .countResultType
        do {
            return try store.managedObjectContext.count(for: request)
        } catch let error {
            MXLog.error("[MXCoreDataRoomListDataFetcher] failed to count rooms: \(error)")
            return 0
        }
    }
    
    internal init(fetchOptions: MXRoomListDataFetchOptions,
                  store: MXRoomSummaryCoreDataContextableStore) {
        self.fetchOptions = fetchOptions
        self.store = store
        super.init()
        self.fetchOptions.fetcher = self
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
    
    func paginate() {
        guard let oldData = data else {
            //  load first page
            performFetch()
            return
        }
        
        guard oldData.hasMoreRooms else {
            //  no more rooms
            return
        }
        removeCacheIfRequired()
        let numberOfItems = (oldData.currentPage + 2) * oldData.paginationOptions.rawValue
        fetchedResultsController.fetchRequest.fetchLimit = numberOfItems
        performFetch()
    }
    
    func resetPagination() {
        removeCacheIfRequired()
        fetchedResultsController.fetchRequest.fetchLimit = fetchOptions.paginationOptions.rawValue
        performFetch()
    }
    
    func refresh() {
        guard let oldData = data else {
            return
        }
        data = nil
        recomputeData(using: oldData)
    }
    
    func stop() {
        fetchedResultsController.delegate = nil
        removeCacheIfRequired()
    }
    
    //  MARK: - Private
    
    private func removeCacheIfRequired() {
        if let cacheName = fetchedResultsController.cacheName {
            NSFetchedResultsController<NSFetchRequestResult>.deleteCache(withName: cacheName)
        }
    }
    
    private func performFetch() {
        do {
            try fetchedResultsController.performFetch()
            computeData()
        } catch let error {
            MXLog.error("[MXCoreDataRoomListDataFetcher] failed to perform fetch: \(error)")
        }
    }
    
    private func notifyDataChange() {
        multicastDelegate.invoke({ $0.fetcherDidChangeData(self) })
    }
    
    /// Recompute data with the same number of rooms of the given `data`
    private func recomputeData(using data: MXRoomListData) {
        removeCacheIfRequired()
        let numberOfItems = (data.currentPage + 1) * data.paginationOptions.rawValue
        fetchedResultsController.fetchRequest.predicate = filterPredicate(for: filterOptions)
        fetchedResultsController.fetchRequest.sortDescriptors = sortDescriptors(for: sortOptions)
        fetchedResultsController.fetchRequest.fetchLimit = numberOfItems
        performFetch()
    }
    
    private func computeData() {
        guard let summaries = fetchedResultsController.fetchedObjects else {
            data = nil
            return
        }
        
        let mapped = summaries.compactMap({ MXRoomSummary(summaryModel: $0) })
        
        let counts = MXStoreRoomListDataCounts(withRooms: mapped,
                                               totalRoomsCount: totalRoomsCount)
        data = MXRoomListData(rooms: mapped,
                              counts: counts,
                              paginationOptions: fetchOptions.paginationOptions)
        fetchedResultsController.delegate = self
    }
    
}

//  MARK: MXRoomListDataSortable

extension MXCoreDataRoomListDataFetcher: MXRoomListDataSortable {
    
    var sortOptions: MXRoomListDataSortOptions {
        return fetchOptions.sortOptions
    }
    
    func sortDescriptors(for sortOptions: MXRoomListDataSortOptions) -> [NSSortDescriptor] {
        var result: [NSSortDescriptor] = []
        
        if sortOptions.invitesFirst {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryModel.s_membershipInt, ascending: true))
        }
        
        if sortOptions.sentStatus {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryModel.s_sentStatusInt, ascending: false))
        }
        
        if sortOptions.missedNotificationsFirst {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryModel.s_highlightCount, ascending: false))
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryModel.s_notificationCount, ascending: false))
        }
        
        if sortOptions.unreadMessagesFirst {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryModel.s_localUnreadEventCount, ascending: false))
        }
        
        if sortOptions.lastEventDate {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryModel.s_lastMessage?.s_originServerTs, ascending: false))
        }
        
        if sortOptions.favoriteTag {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryModel.s_favoriteTagOrder, ascending: false))
        }
        
        return result
    }
    
}

//  MARK: MXRoomListDataFilterable

extension MXCoreDataRoomListDataFetcher: MXRoomListDataFilterable {
    
    var filterOptions: MXRoomListDataFilterOptions {
        return fetchOptions.filterOptions
    }
    
    func filterPredicate(for filterOptions: MXRoomListDataFilterOptions) -> NSPredicate? {
        var subpredicates: [NSPredicate] = []
        
        if let space = filterOptions.space {
            let subpredicate = NSPredicate(format: "%@ IN %K",
                                           #keyPath(MXRoomSummaryModel.s_parentSpaceIds), space)
            subpredicates.append(subpredicate)
        }
        
        if let query = filterOptions.query, !query.isEmpty {
            let subpredicate = NSPredicate(format: "%K CONTAINS[cd] %@",
                                           #keyPath(MXRoomSummaryModel.s_displayName), query)
            subpredicates.append(subpredicate)
        }
        
        if !filterOptions.onlySuggested {
            if !filterOptions.dataTypes.isEmpty {
                let subpredicate = NSPredicate(format: "(%K & %d) != 0",
                                               #keyPath(MXRoomSummaryModel.s_dataTypesInt), filterOptions.dataTypes.rawValue)
                subpredicates.append(subpredicate)
            }
            
            if !filterOptions.notDataTypes.isEmpty {
                let subpredicate = NSPredicate(format: "(%K & %d) == 0",
                                               #keyPath(MXRoomSummaryModel.s_dataTypesInt), filterOptions.notDataTypes.rawValue)
                subpredicates.append(subpredicate)
            }
        }
        
        guard !subpredicates.isEmpty else {
            return nil
        }
        
        if subpredicates.count == 1 {
            return subpredicates.first
        }
        return NSCompoundPredicate(type: .and,
                                   subpredicates: subpredicates)
    }
    
}

//  MARK: - NSFetchedResultsControllerDelegate

extension MXCoreDataRoomListDataFetcher: NSFetchedResultsControllerDelegate {
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        computeData()
    }
    
}

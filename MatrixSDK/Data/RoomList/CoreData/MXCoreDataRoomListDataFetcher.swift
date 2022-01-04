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
    
    private weak var session: MXSession?
    internal let fetchOptions: MXRoomListDataFetchOptions
    private lazy var initialSyncThrottler: MXThrottler = {
        return MXThrottler(minimumDelay: 1.0, queue: .main)
    }()
    private lazy var dataUpdateThrottler: MXThrottler = {
        return MXThrottler(minimumDelay: 0.1, queue: .main)
    }()
    
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
    
    private lazy var fetchedResultsController: NSFetchedResultsController<MXRoomSummaryMO> = {
        let request = MXRoomSummaryMO.typedFetchRequest()
        request.predicate = filterPredicate(for: filterOptions)
        request.sortDescriptors = sortDescriptors(for: sortOptions)
        request.fetchLimit = fetchOptions.paginationOptions.rawValue
        let controller = NSFetchedResultsController(fetchRequest: request,
                                                    managedObjectContext: store.mainManagedObjectContext,
                                                    sectionNameKeyPath: nil,
                                                    cacheName: nil)
        controller.delegate = self
        return controller
    }()
    
    private var totalRoomsCount: Int {
        let request = MXRoomSummaryMO.typedFetchRequest()
        request.predicate = filterPredicate(for: filterOptions)
        request.resultType = .countResultType
        do {
            return try store.mainManagedObjectContext.count(for: request)
        } catch let error {
            MXLog.error("[MXCoreDataRoomListDataFetcher] failed to count rooms: \(error)")
            return 0
        }
    }
    
    private var totalCounts: MXRoomListDataCounts? {
        guard fetchOptions.paginationOptions != .none else {
            return nil
        }
        let request = MXRoomSummaryMO.typedFetchRequest()
        request.predicate = filterPredicate(for: filterOptions)
        let propertyNames: [String] = ["s_dataTypesInt", "s_sentStatusInt", "s_notificationCount", "s_highlightCount"]
        var properties: [NSPropertyDescription] = []
        
        for propertyName in propertyNames {
            guard let property = MXRoomSummaryMO.entity().propertiesByName[propertyName] else {
                fatalError("[MXCoreDataRoomSummaryStore] Couldn't find \(propertyName) on entity \(String(describing: MXRoomSummaryMO.self)), probably property name changed")
            }
            properties.append(property)
        }
        request.propertiesToFetch = properties
        do {
            let summaries = try store.mainManagedObjectContext.fetch(request)
            return MXStoreRoomListDataCounts(withRooms: summaries,
                                             total: nil)
        } catch let error {
            MXLog.error("[MXCoreDataRoomListDataFetcher] failed to calculate total counts: \(error)")
            return nil
        }
    }
    
    internal init(session: MXSession?,
                  fetchOptions: MXRoomListDataFetchOptions,
                  store: MXRoomSummaryCoreDataContextableStore) {
        self.session = session
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
        fetchedResultsController.fetchRequest.fetchLimit = numberOfItems > 0 ? numberOfItems : 0
        performFetch()
    }
    
    func resetPagination() {
        removeCacheIfRequired()
        let numberOfItems = fetchOptions.paginationOptions.rawValue
        fetchedResultsController.fetchRequest.fetchLimit = numberOfItems > 0 ? numberOfItems : 0
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
        fetchedResultsController.fetchRequest.fetchLimit = numberOfItems > 0 ? numberOfItems : 0
        performFetch()
    }
    
    private func computeData() {
        guard let summaries = fetchedResultsController.fetchedObjects else {
            data = nil
            return
        }
        
        let fetchLimit = fetchedResultsController.fetchRequest.fetchLimit
        let mapped: [MXRoomSummary]
        
        if fetchLimit > 0 && summaries.count > fetchLimit {
            data = nil
            mapped = summaries[0..<fetchLimit].compactMap { MXRoomSummary(summaryModel: $0) }
        } else {
            mapped = summaries.compactMap { MXRoomSummary(summaryModel: $0) }
        }
        let counts = MXStoreRoomListDataCounts(withRooms: mapped,
                                               total: totalCounts)
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
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryMO.s_membershipInt, ascending: true))
        }
        
        if sortOptions.sentStatus {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryMO.s_sentStatusInt, ascending: false))
        }
        
        if sortOptions.missedNotificationsFirst {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryMO.s_hasAnyHighlight, ascending: false))
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryMO.s_hasAnyNotification, ascending: false))
        }
        
        if sortOptions.unreadMessagesFirst {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryMO.s_hasAnyUnread, ascending: false))
        }
        
        if sortOptions.lastEventDate {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryMO.s_lastMessage?.s_originServerTs, ascending: false))
        }
        
        if sortOptions.favoriteTag {
            result.append(NSSortDescriptor(keyPath: \MXRoomSummaryMO.s_favoriteTagOrder, ascending: false))
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
        var predicates: [NSPredicate] = []
        
        if !filterOptions.onlySuggested {
            if filterOptions.hideUnknownMembershipRooms {
                let memberPredicate = NSPredicate(format: "%K != %d",
                                                  #keyPath(MXRoomSummaryMO.s_membershipInt),
                                                  MXMembership.unknown.rawValue)
                predicates.append(memberPredicate)
            }
            
            //  data types
            if !filterOptions.dataTypes.isEmpty {
                let predicate = NSPredicate(format: "(%K & %d) != 0",
                                            #keyPath(MXRoomSummaryMO.s_dataTypesInt),
                                            filterOptions.dataTypes.rawValue)
                predicates.append(predicate)
            }
            
            //  not data types
            if !filterOptions.notDataTypes.isEmpty {
                let predicate = NSPredicate(format: "(%K & %d) == 0",
                                            #keyPath(MXRoomSummaryMO.s_dataTypesInt),
                                            filterOptions.notDataTypes.rawValue)
                predicates.append(predicate)
            }
            
            //  space
            if let space = filterOptions.space {
                //  specific space
                let predicate = NSPredicate(format: "%K CONTAINS[c] %@",
                                            #keyPath(MXRoomSummaryMO.s_parentSpaceIds),
                                            space.spaceId)
                predicates.append(predicate)
            } else {
                //  home space
                
                // In case of home space we show a room if one of the following conditions is true:
                // - Show All Rooms is enabled
                // - It's a direct room
                // - The room is a favourite
                // - The room is orphaned
                
                let predicate1 = NSPredicate(value: filterOptions.showAllRoomsInHomeSpace)
                
                let directDataTypes: MXRoomSummaryDataTypes = .direct
                let predicate2 = NSPredicate(format: "(%K & %d) != 0",
                                             #keyPath(MXRoomSummaryMO.s_dataTypesInt),
                                             directDataTypes.rawValue)
                
                let favoritedDataTypes: MXRoomSummaryDataTypes = .favorited
                let predicate3 = NSPredicate(format: "(%K & %d) != 0",
                                             #keyPath(MXRoomSummaryMO.s_dataTypesInt),
                                             favoritedDataTypes.rawValue)
                
                let predicate4 = NSPredicate(format: "%K MATCHES %@",
                                             #keyPath(MXRoomSummaryMO.s_parentSpaceIds),
                                             "^$")
                
                let predicate = NSCompoundPredicate(type: .or,
                                                    subpredicates: [predicate1, predicate2, predicate3, predicate4])
                predicates.append(predicate)
            }
        }
        
        //  query
        if let query = filterOptions.query, !query.isEmpty {
            let predicate = NSPredicate(format: "%K CONTAINS[cd] %@",
                                        #keyPath(MXRoomSummaryMO.s_displayName),
                                        query)
            predicates.append(predicate)
        }
        
        guard !predicates.isEmpty else {
            return nil
        }
        
        if predicates.count == 1 {
            return predicates.first
        }
        return NSCompoundPredicate(type: .and,
                                   subpredicates: predicates)
    }
    
}

//  MARK: - NSFetchedResultsControllerDelegate

extension MXCoreDataRoomListDataFetcher: NSFetchedResultsControllerDelegate {
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if session?.isEventStreamInitialised == true {
            dataUpdateThrottler.throttle {
                self.computeData()
            }
        } else {
            initialSyncThrottler.throttle {
                self.computeData()
            }
        }
    }
    
}

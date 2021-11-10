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

/// A class to help coordinate the session's main store with any secondary
/// stores that it relies upon such as aggregations. It will ensure that actions
/// which need synchronisation (such as deleting all data) are handled properly.
@objcMembers
public class MXStoreService: NSObject {
    
    // MARK: - Constants
    private enum Constants {
        // Namespace to avoid conflict with any defaults set in the app.
        static let storesToResetKey = "MatrixSDK:storesToReset"
    }
    
    private enum StoreType: String {
        case aggregations
    }
    
    // MARK: - Properties
    
    let credentials: MXCredentials
    
    public let mainStore: MXStore
    
    public var aggregations: MXAggregations? {
        didSet {
            if shouldResetStore(.aggregations) {
                aggregations?.resetData()
                removeStoreToReset(.aggregations)
            }
        }
    }
    
    // MARK: - Setup
    
    public init(store: MXStore, credentials: MXCredentials) {
        self.credentials = credentials
        self.mainStore = store
        
        super.init()
        
        mainStore.storeService = self
    }
    
    // MARK: - Public
    
    /// Reset any secondary stores in the service. This should be called by the main
    /// store if it is permanent, in order to keep all of the data in sync across stores.
    /// - Parameter sender: The file store that is about to delete its data.
    public func resetSecondaryStores(sender: MXFileStore) {
        guard sender == mainStore as? MXFileStore else {
            MXLog.error("[MXStoreService] resetSecondaryStores called by the wrong store.")
            return
        }
        
        MXLog.debug("[MXStoreService] Reset secondary stores")
        
        if let aggregations = aggregations {
            aggregations.resetData()
        } else {
            // It is possible that aggregations doesn't exist (for example in MXBackgroundStore),
            // In this instance, remember to reset the aggregations store when it is set.
            addStoreToReset(.aggregations)
            MXLog.debug("[MXStoreService] Aggregations will be reset when added to the service.")
        }
    }
    
    /// Close all stores in the service.
    public func closeStores() {
        mainStore.close?()
        
        // MXAggregations doesn't require closing.
    }
    
    // MARK: - Stores with credentials
    
    /// Whether or not the specified store type needs to be reset for the current user ID.
    private func shouldResetStore(_ storeType: StoreType) -> Bool {
        guard let userId = credentials.userId else { return false }
        return storesToReset(for: userId).contains(storeType)
    }
    
    /// Add a store that should be reset later for the current user ID.
    private func addStoreToReset(_ storeType: StoreType) {
        guard let userId = credentials.userId else { return }
        
        var storeTypes = storesToReset(for: userId)
        storeTypes.append(storeType)
        
        updateStoresToReset(storeTypes, for: userId)
    }
    
    /// Marks a store as having been reset for the current user ID.
    /// This only needs to be called if `shouldResetStore` was true.
    private func removeStoreToReset(_ storeType: StoreType) {
        guard let userId = credentials.userId else { return }
        
        var storeTypes = storesToReset(for: userId)
        storeTypes.removeAll { $0 == storeType }
        
        updateStoresToReset(storeTypes, for: userId)
    }
    
    // MARK: - All Stores
    
    private var defaults: UserDefaults {
        UserDefaults(suiteName: MXSDKOptions.sharedInstance().applicationGroupIdentifier) ?? UserDefaults.standard
    }
    
    /// All store types that should be reset when loaded for the specified user ID
    /// - Parameter userId: The user ID to check with.
    /// - Returns: An array of store types.
    private func storesToReset(for userId: String) -> [StoreType] {
        let allStoresToReset = defaults.object(forKey: Constants.storesToResetKey) as? [String: [String]] ?? [:]
        let userStoreTypes = allStoresToReset[userId] ?? []
        
        return userStoreTypes.compactMap { StoreType(rawValue: $0) }
    }
    
    /// Update the store types that need to be reset when loaded for the specified user ID.
    /// - Parameters:
    ///   - storeTypes: The store types that should be reset.
    ///   - userId: The user ID to store the types for.
    private func updateStoresToReset(_ storeTypes: [StoreType], for userId: String) {
        var allStoresToReset = defaults.object(forKey: Constants.storesToResetKey) as? [String: [String]] ?? [:]
        allStoresToReset[userId] = storeTypes.map { $0.rawValue }
        
        defaults.setValue(allStoresToReset, forKey: Constants.storesToResetKey)
    }
}

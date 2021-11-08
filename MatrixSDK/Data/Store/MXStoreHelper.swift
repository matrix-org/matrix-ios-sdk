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
public class MXStoreHelper: NSObject {
    private enum Constants {
        // Namespace to avoid conflict with any defaults set in the app.
        static let storesToClearKey = "MatrixSDK:secondaryStoresToClear"
    }
    
    // MARK: - Public
    
    /// Whether or not secondary stores such as `MXAggregations` should be cleared for the specified user.
    /// - Parameter userId: The user ID to check for.
    /// - Returns: `true` if the stores should be cleared.
    public static func shouldSecondaryStoresBeCleared(for userId: String) -> Bool {
        secondaryStoresToClear.contains(userId)
    }
    
    /// Indicates that any secondary stores such as `MXAggregations` should be cleared the next time
    /// they are opened. This should be called when `MXFileStore` deleted all of its data at a point in
    /// time when other stores aren't available.
    /// - Parameter userId: The user ID whose stores need clearing.
    public static func setSecondaryStoresToBeCleared(for userId: String) {
        var existingUserIds = secondaryStoresToClear
        existingUserIds.insert(userId)
        secondaryStoresToClear = existingUserIds
    }
    
    /// Indicates the any secondary stores such as `MXAggregations` have now been cleared for
    /// the specified user.
    /// - Parameter userId: The user ID whose stores were just cleared.
    public static func secondaryStoresWereCleared(for userId: String) {
        var existingUserIds = secondaryStoresToClear
        existingUserIds.remove(userId)
        secondaryStoresToClear = existingUserIds
    }
    
    // MARK: - Private
    
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: MXSDKOptions.sharedInstance().applicationGroupIdentifier) ?? UserDefaults.standard
    }
    
    private static var secondaryStoresToClear: Set<String> {
        get {
            let storedUserIds = defaults.object(forKey: Constants.storesToClearKey) as? [String] ?? []
            return Set(storedUserIds)
        }
        set {
            defaults.setValue(Array(newValue), forKey: Constants.storesToClearKey)
        }
    }
}

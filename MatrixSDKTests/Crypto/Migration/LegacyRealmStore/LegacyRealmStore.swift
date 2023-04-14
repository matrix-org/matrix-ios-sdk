// 
// Copyright 2023 The Matrix.org Foundation C.I.C
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
import Realm

/// Class simulating legacy crypto store associated with the now-deprecated native crypto module
///
/// It has access to several pre-made realm files with legacy accounts that can be loaded
/// and migrated to current crypto module
class LegacyRealmStore {
    enum Error: Swift.Error {
        case missingDependencies
    }
    
    /// A few pre-created accounts with hardcoded details
    enum Account {
        
        /// Realm store with crypto version `version2`, used for migration testing
        case version2
        
        /// Realm store with crypto version `deprecated1`, used for migration testing
        case deprecated1
        
        /// Realm store with crypto version `deprecated3`, used for migration testing
        case deprecated3
        
        /// Realm store with a verified accounts used to test cross-signing migration
        case verified
        
        /// Realm store with an unverified accounts used to test cross-signing migration
        case unverified
        
        /// File name for the associated account file
        var fileName: String {
            switch self {
            case .version2:
                return "legacy_version2_account"
            case .deprecated1:
                return "legacy_deprecated1_account"
            case .deprecated3:
                return "legacy_deprecated3_account"
            case .verified:
                return "legacy_verified_account"
            case .unverified:
                return "legacy_unverified_account"
            }
        }
        
        /// Hardcoded room id matching a given account
        var roomId: String? {
            switch self {
            case .version2:
                return nil
            case .deprecated1:
                return nil
            case .deprecated3:
                return nil
            case .verified:
                return "!QUWVMCIhJqIqTMLxof:x.y.z"
            case .unverified:
                return nil
            }
        }
        
        /// Hardcoded account credentials matching a given account
        var credentials: MXCredentials {
            let cred = MXCredentials()
            switch self {
            case .version2:
                cred.userId = "@mxalice-54aeab93-b4b2-4edf-85e1-bc0dbbb710ee:x.y.z"
                cred.deviceId = "NAHEYWCBBM"
            case .deprecated1:
                cred.userId = "@mxalice-d9eed33b-e269-4171-9352-8ee8b84b37a1:x.y.z"
                cred.deviceId = "KLWNEPIHMX"
            case .deprecated3:
                cred.userId = "@mxalice-4c5a01ea-9fac-4568-bda6-09e2d14f0e5d:x.y.z"
                cred.deviceId = "DCGBYVZFQI"
            case .verified:
                cred.userId = "@mxalice-107ca1c5-4d03-4ff4-affc-369f4ce6de6f:x.y.z"
                cred.deviceId = "AXDAYKSETI"
            case .unverified:
                cred.userId = "@mxalice-f5314669-7d43-4662-8262-771728e1921f:x.y.z"
                cred.deviceId = "ELSGFERWHH"
            }
            return cred
        }
    }
    
    static func load(account: Account) throws -> MXRealmCryptoStore {
        guard
            let sourceUrl = Bundle(for: Self.self).url(forResource: account.fileName, withExtension: "realm"),
            let folder = realmFolder()
        else {
            throw Error.missingDependencies
        }
        
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    
        let credentials = account.credentials
        let file = "\(credentials.userId!)-\(credentials.deviceId!).realm"
    
        let targetUrl = folder.appendingPathComponent(file)
        if FileManager.default.fileExists(atPath: targetUrl.path) {
            try FileManager.default.removeItem(at: targetUrl)
        }
        
        try FileManager.default.copyItem(at: sourceUrl, to: targetUrl)
        return MXRealmCryptoStore(credentials: credentials)
    }
    
    static func hasData(for account: Account) -> Bool {
        let credentials = account.credentials
        let file = "\(credentials.userId!)-\(credentials.deviceId!).realm"
        
        return MXRealmCryptoStore.hasData(for: credentials)
    }
    
    static func deleteAllStores() throws {
        guard let folder = realmFolder() else {
            throw Error.missingDependencies
        }
        
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }
    
    private static func realmFolder() -> URL? {
        platformDirectoryURL()?
            .appendingPathComponent("MXRealmCryptoStore")
    }
    
    private static func platformDirectoryURL() -> URL? {
        #if os(OSX)
        guard
            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            let identifier = Bundle.main.bundleIdentifier
        else {
            return nil
        }
        return applicationSupport.appendingPathComponent(identifier)
        #else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        #endif
    }
}

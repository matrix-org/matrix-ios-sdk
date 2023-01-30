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

struct MXCryptoMachineStore {
    enum Error: Swift.Error {
        case invalidStorage
        case invalidPassphrase
    }
    
    private static let storeFolder = "MXCryptoStore"
    
    static func createStoreURLIfNecessary(for userId: String) throws -> URL {
        let containerURL = try storeContainerURL()
        if !FileManager.default.fileExists(atPath: containerURL.path) {
            try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        }
        return try storeURL(for: userId)
    }
    
    static func storeURL(for userId: String) throws -> URL {
        return try storeContainerURL()
            .appendingPathComponent(userId)
    }
    
    static func storePassphrase() throws -> String {
        let key = MXKeyProvider.sharedInstance()
            .keyDataForData(
                ofType: MXCryptoSDKStoreKeyDataType,
                isMandatory: true,
                expectedKeyType: .rawData
            )
        
        guard let key = key as? MXRawDataKey else {
            throw Error.invalidPassphrase
        }
        
        return MXBase64Tools.base64(from: key.key)
    }
    
    private static func storeContainerURL() throws -> URL {
        let container: URL
        if let sharedContainerURL = FileManager.default.applicationGroupContainerURL() {
            container = sharedContainerURL
        } else if let url = platformDirectoryURL() {
            container = url
        } else {
            throw Error.invalidStorage
        }

        return container
            .appendingPathComponent(Self.storeFolder)
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

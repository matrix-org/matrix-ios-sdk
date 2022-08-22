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

public extension FileManager {
    /**
     Create a directory at a url, including intermediate directories, which is excluded from iCloud / manual backups, no matter where it is located.
     
     Note: some directories are excluded automatically if they are nested within `<AppHome>/Library/Caches/` or `<AppHome>/tmp/`
     see [details](https://developer.apple.com/documentation/foundation/optimizing_app_data_for_icloud_backup).
     */
    @objc func createDirectoryExcludedFromBackup(at url: URL) throws {
        try createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        try excludeItemFromBackup(at: url)
    }
    
    /**
     Create a directory at a path, including intermediate directories, which is excluded from iCloud / manual backups, no matter where it is located.
     
     Note: some directories are excluded automatically if they are nested within `<AppHome>/Library/Caches/` or `<AppHome>/tmp/`
     see [details](https://developer.apple.com/documentation/foundation/optimizing_app_data_for_icloud_backup).
     */
    @objc func createDirectoryExcludedFromBackup(atPath path: String) throws {
        try createDirectoryExcludedFromBackup(at: URL(fileURLWithPath: path))
    }
    
    /**
     Exclude a given url from iCloud / manual backups, no matter where it is located.
     
     Note: some directories are excluded automatically if they are nested within `<AppHome>/Library/Caches/` or `<AppHome>/tmp/`
     see [details](https://developer.apple.com/documentation/foundation/optimizing_app_data_for_icloud_backup).
     */
    @objc func excludeItemFromBackup(at url: URL) throws {
        try (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
    }
    
    /**
     Exclude all user directories from iCloud / manual backups.
     
     User directories include `<AppHome>/Documents`, `<AppHome>/Library`, `<AppHome>/Library/Application Support` etc.
     Some directories are excluded automatically if they are nested within `<AppHome>/Library/Caches/` or `<AppHome>/tmp/`
     */
    func excludeAllUserDirectoriesFromBackup() {
        // Only `Documents` and `Library` directories need to be specified explicitly. Other directories are either excluded
        // automatically (`tmp`, `Library/Caches`), or are nested within one of the excluded ones (e.g. `Library/Application Support`)
        let urls = [
            urls(for: .documentDirectory, in: .userDomainMask),
            urls(for: .libraryDirectory, in: .userDomainMask)
        ].flatMap { $0 }
        
        for url in urls {
            do {
                try excludeItemFromBackup(at: url)
            } catch {
                MXLog.error("[FileManager+Backup]: Cannot exclude url from backup", context: error)
            }
        }
    }
    
    /**
     Exclude all files and directories inside a shared `AppGroup` container from iCloud / manual backups.
     
     Note: the current application will only exclude files / directories for which it has write permissions, typically those which it created.
     Other files and directories will be unaffected.
     */
    func excludeAllAppGroupDirectoriesFromBackup() {
        guard let container = applicationGroupContainerURL() else {
            return
        }
        
        // The `AppGroup` container cannot be modified directly, as it is potentially shared between multiple applications.
        // Instead of that the individial files and directories without the `AppGroup` root can be excluded individually.
        let urls: [URL]
        do {
            urls = try contentsOfDirectory(at: container, includingPropertiesForKeys: nil, options: [])
        } catch {
            MXLog.error("[FileManager+Backup]: Cannot get contents of container", context: error)
            return
        }
        
        for url in urls where isWritableFile(atPath: url.path) {
            do {
                try excludeItemFromBackup(at: url)
            } catch {
                MXLog.error("[FileManager+Backup]: Cannot exclude url from backup", context: error)
            }
        }
    }
}

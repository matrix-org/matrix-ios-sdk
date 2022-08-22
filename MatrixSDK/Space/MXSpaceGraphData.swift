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

/// MXSpaceGraphData aims to store all the data needed for the space graph
class MXSpaceGraphData: NSObject, NSCoding {
    
    // MARK: - Constants
    
    private enum Constants {
        static let spaceRoomIdsKey: String = "spaceRoomIds"
        static let parentIdsPerRoomIdKey: String = "parentIdsPerRoomId"
        static let ancestorsPerRoomIdKey: String = "ancestorsPerRoomId"
        static let descendantsPerRoomIdKey: String = "descendantsPerRoomId"
        static let rootSpaceIdsKey: String = "rootSpaceIds"
        static let orphanedRoomIdsKey: String = "orphanedRoomIds"
        static let orphanedDirectRoomIdsKey: String = "orphanedDirectRoomIds"
    }
    
    // MARK: - Properties
    
    /// Array of all space IDs for the session
    let spaceRoomIds: [String]
    
    /// List of IDs of the direct parents for each room ID
    let parentIdsPerRoomId: [String : Set<String>]
    
    /// List of IDs of the ancestors (recursive parents) for each room ID
    let ancestorsPerRoomId: [String: Set<String>]

    /// List of IDs of the descendants (recursive children) for each room ID
    let descendantsPerRoomId: [String: Set<String>]

    /// List of space IDs for spaces without parents
    let rootSpaceIds: [String]
    
    /// List of all rooms without space
    let orphanedRoomIds: Set<String>
    
    /// List of all direct rooms without space
    let orphanedDirectRoomIds: Set<String>
    
    // MARK: - Public
    
    override init() {
        self.spaceRoomIds = []
        self.parentIdsPerRoomId = [:]
        self.ancestorsPerRoomId = [:]
        self.descendantsPerRoomId = [:]
        self.rootSpaceIds = []
        self.orphanedRoomIds = []
        self.orphanedDirectRoomIds = []

        super.init()
    }
    
    init(spaceRoomIds: [String],
         parentIdsPerRoomId: [String : Set<String>],
         ancestorsPerRoomId: [String: Set<String>],
         descendantsPerRoomId: [String: Set<String>],
         rootSpaceIds: [String],
         orphanedRoomIds: Set<String>,
         orphanedDirectRoomIds: Set<String>) {
        self.spaceRoomIds = spaceRoomIds
        self.parentIdsPerRoomId = parentIdsPerRoomId
        self.ancestorsPerRoomId = ancestorsPerRoomId
        self.descendantsPerRoomId = descendantsPerRoomId
        self.rootSpaceIds = rootSpaceIds
        self.orphanedRoomIds = orphanedRoomIds
        self.orphanedDirectRoomIds = orphanedDirectRoomIds
    }
    
    // MARK: - NSCoding
    
    func encode(with coder: NSCoder) {
        coder.encode(self.spaceRoomIds, forKey: Constants.spaceRoomIdsKey)
        coder.encode(self.parentIdsPerRoomId, forKey: Constants.parentIdsPerRoomIdKey)
        coder.encode(self.ancestorsPerRoomId, forKey: Constants.ancestorsPerRoomIdKey)
        coder.encode(self.descendantsPerRoomId, forKey: Constants.descendantsPerRoomIdKey)
        coder.encode(self.rootSpaceIds, forKey: Constants.rootSpaceIdsKey)
        coder.encode(self.orphanedRoomIds, forKey: Constants.orphanedRoomIdsKey)
        coder.encode(self.orphanedDirectRoomIds, forKey: Constants.orphanedDirectRoomIdsKey)
    }
    
    required init(coder: NSCoder) {
        self.spaceRoomIds = coder.decodeObject(forKey: Constants.spaceRoomIdsKey) as? [String] ?? []
        self.parentIdsPerRoomId = coder.decodeObject(forKey: Constants.parentIdsPerRoomIdKey) as? [String : Set<String>] ?? [:]
        self.ancestorsPerRoomId = coder.decodeObject(forKey: Constants.ancestorsPerRoomIdKey) as? [String : Set<String>] ?? [:]
        self.descendantsPerRoomId = coder.decodeObject(forKey: Constants.descendantsPerRoomIdKey) as? [String : Set<String>] ?? [:]
        self.rootSpaceIds = coder.decodeObject(forKey: Constants.rootSpaceIdsKey) as? [String] ?? []
        self.orphanedRoomIds = coder.decodeObject(forKey: Constants.orphanedRoomIdsKey) as? Set<String> ?? Set()
        self.orphanedDirectRoomIds = coder.decodeObject(forKey: Constants.orphanedDirectRoomIdsKey) as? Set<String> ?? Set()
    }

    // MARK: - JSON format
    
    func jsonDictionary() -> [String : Any]! {
        return [
            Constants.spaceRoomIdsKey: self.spaceRoomIds,
            Constants.parentIdsPerRoomIdKey: self.parentIdsPerRoomId,
            Constants.ancestorsPerRoomIdKey: self.ancestorsPerRoomId,
            Constants.descendantsPerRoomIdKey: self.descendantsPerRoomId,
            Constants.rootSpaceIdsKey: self.rootSpaceIds,
            Constants.orphanedRoomIdsKey: self.orphanedRoomIds,
            Constants.orphanedDirectRoomIdsKey: self.orphanedDirectRoomIds
        ]
    }
    
    class func model(fromJSON dictionary: [AnyHashable : Any]!) -> MXSpaceGraphData? {
        guard let spaceIdsJson = dictionary[Constants.spaceRoomIdsKey] as? [String] else {
            MXLog.error("[MXSpaceGraphData] model fromJSON aborted: missing spaceRoomIdsKey")
            return nil
        }
        guard let parentIdsPerRoomIdJson = dictionary[Constants.parentIdsPerRoomIdKey] as? [String : [String]] else {
            MXLog.error("[MXSpaceGraphData] model fromJSON aborted: missing parentIdsPerRoomIdKey")
            return nil
        }
        guard let ancestorsPerRoomIdJson = dictionary[Constants.ancestorsPerRoomIdKey] as? [String : [String]] else {
            MXLog.error("[MXSpaceGraphData] model fromJSON aborted: missing ancestorsPerRoomIdKey")
            return nil
        }
        guard let descendantsPerRoomIdJson = dictionary[Constants.descendantsPerRoomIdKey] as? [String : [String]] else {
            MXLog.error("[MXSpaceGraphData] model fromJSON aborted: missing descendantsPerRoomIdKey")
            return nil
        }
        guard let rootSpaceIdsJson = dictionary[Constants.rootSpaceIdsKey] as? [String] else {
            MXLog.error("[MXSpaceGraphData] model fromJSON aborted: missing rootSpaceIdsKey")
            return nil
        }
        guard let orphanedRoomIdsJson = dictionary[Constants.orphanedRoomIdsKey] as? [String] else {
            MXLog.error("[MXSpaceGraphData] model fromJSON aborted: missing orphanedRoomIdsKey")
            return nil
        }
        guard let orphanedDirectRoomIdsJson = dictionary[Constants.orphanedDirectRoomIdsKey] as? [String] else {
            MXLog.error("[MXSpaceGraphData] model fromJSON aborted: missing orphanedDirectRoomIdsKey")
            return nil
        }

        var parentIdsPerRoomId: [String : Set<String>] = [:]
        var ancestorsPerRoomId: [String: Set<String>] = [:]
        var descendantsPerRoomId: [String: Set<String>] = [:]
        var orphanedRoomIds: Set<String> = Set()
        var orphanedDirectRoomIds: Set<String> = Set()

        parentIdsPerRoomIdJson.forEach { (key: String, value: [String]) in
            parentIdsPerRoomId[key] = Set<String>(value)
        }
        
        ancestorsPerRoomIdJson.forEach { (key: String, value: [String]) in
            ancestorsPerRoomId[key] = Set<String>(value)
        }

        descendantsPerRoomIdJson.forEach { (key: String, value: [String]) in
            descendantsPerRoomId[key] = Set<String>(value)
        }

        orphanedRoomIds = Set<String>(orphanedRoomIdsJson)
        orphanedDirectRoomIds = Set<String>(orphanedDirectRoomIdsJson)

        return MXSpaceGraphData(spaceRoomIds: spaceIdsJson,
                                parentIdsPerRoomId: parentIdsPerRoomId,
                                ancestorsPerRoomId: ancestorsPerRoomId,
                                descendantsPerRoomId: descendantsPerRoomId,
                                rootSpaceIds: rootSpaceIdsJson,
                                orphanedRoomIds: orphanedRoomIds,
                                orphanedDirectRoomIds: orphanedDirectRoomIds)
    }
}

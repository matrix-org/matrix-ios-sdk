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

@objcMembers
public class MXLRUCache: NSObject {

    private var cachedObjects: [LRUCacheItem] = []
    private let capacity: UInt

    private static let queue = DispatchQueue(label: "LRUCache")


    public init(capacity: UInt) {
        self.capacity = capacity
        super.init()
    }

    public func get(_ key: String) -> AnyObject? {
        Self.queue.sync {
            guard
                let item = cachedObjects.first(where: { $0.key == key })
            else { return nil }
            item.refCount += 1
            sortCachedItems()
            return item
        }
    }

    public func put(_ key: String, object: AnyObject?) {
        Self.queue.sync {
            guard
                cachedObjects.firstIndex(where: { $0.key == key }) == nil
            else { return }

            let newItem = LRUCacheItem(object: object, key: key)

            if cachedObjects.count > capacity {
                cachedObjects.removeLast()
            }

            cachedObjects.append(newItem)
        }
    }

    public func clear() {
        Self.queue.sync {
            cachedObjects.removeAll()
        }
    }

    private func sortCachedItems() {
        cachedObjects.sort {
            $0.refCount > $1.refCount
        }
    }

    private class LRUCacheItem: NSObject {
        var refCount: UInt = 1
        let object: AnyObject?
        let key: String

        init(refCount: UInt = 1, object: AnyObject?, key: String) {
            self.refCount = refCount
            self.object = object
            self.key = key
        }
    }
}

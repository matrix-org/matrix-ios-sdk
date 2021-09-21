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

public class MXMulticastDelegate <T: AnyObject> {
    
    private let delegates: NSHashTable<T> = NSHashTable.weakObjects()
    private let dispatchQueue: DispatchQueue
    
    init(dispatchQueue: DispatchQueue = .main) {
        self.dispatchQueue = dispatchQueue
    }
    
    func addDelegate(_ delegate: T) {
        synchronizeDelegates {
            delegates.add(delegate)
        }
    }
    
    func removeDelegate(_ delegate: T) {
        synchronizeDelegates {
            for oneDelegate in delegates.allObjects.reversed() {
                if oneDelegate === delegate {
                    delegates.remove(oneDelegate)
                }
            }
        }
    }
    
    func removeAllDelegates() {
        synchronizeDelegates {
            delegates.removeAllObjects()
        }
    }
    
    func invoke(invocation: @escaping (T) -> ()) {
        synchronizeDelegates {
            for delegate in delegates.allObjects.reversed() {
                dispatchQueue.async {
                    invocation(delegate)
                }
            }
        }
    }
    
    private func synchronizeDelegates(_ block: () -> Void) {
        objc_sync_enter(delegates)
        block()
        objc_sync_exit(delegates)
    }
    
    deinit {
        removeAllDelegates()
    }
    
}

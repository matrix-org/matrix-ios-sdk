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

/// Util class to handle multiple delegates
public class MXMulticastDelegate <T: AnyObject> {
    
    /// Weakly referenced delegates
    private let delegates: NSHashTable<T> = NSHashTable.weakObjects()
    private let dispatchQueue: DispatchQueue
    private let lockDelegates = NSRecursiveLock()
    
    /// Initializer
    /// - Parameter dispatchQueue: Queue to invoke delegate methods
    public init(dispatchQueue: DispatchQueue = .main) {
        self.dispatchQueue = dispatchQueue
    }
    
    /// Add a delegate instance.
    /// - Parameter delegate: new delegate
    public func addDelegate(_ delegate: T) {
        synchronizeDelegates {
            delegates.add(delegate)
        }
    }
    
    /// Remove a delegate instance
    /// - Parameter delegate: delegate to be removed
    public func removeDelegate(_ delegate: T) {
        synchronizeDelegates {
            for oneDelegate in delegates.allObjects.reversed() {
                if oneDelegate === delegate {
                    delegates.remove(oneDelegate)
                }
            }
        }
    }
    
    /// Remove all delegates
    public func removeAllDelegates() {
        synchronizeDelegates {
            delegates.removeAllObjects()
        }
    }
    
    /// Invoke a delegate method
    /// - Parameter invocation: Block in which delegate objects are traversed
    public func invoke(_ invocation: @escaping (T) -> ()) {
        synchronizeDelegates {
            for delegate in delegates.allObjects.reversed() {
                dispatchQueue.async {
                    invocation(delegate)
                }
            }
        }
    }
    
    /// Thread safe access to delegates array
    private func synchronizeDelegates(_ block: () -> Void) {
        lockDelegates.lock()
        defer { lockDelegates.unlock() }
        block()
    }
    
    deinit {
        removeAllDelegates()
    }
    
}

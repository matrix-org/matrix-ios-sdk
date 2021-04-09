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

/// Scheduler to run one asynchronous or synchronous task at a time.
@objcMembers public class MXAsyncTaskQueue: NSObject {
    
    /// Serial queue where tasks are stacked
    private let dispatchGroupQueue: DispatchQueue
    /// Mechanism to run one task at a time
    private let dispatchGroup: DispatchGroup

    /// Queue from where tasks are executed
    private let dispatchQueue: DispatchQueue
    
    public init(dispatchQueue: DispatchQueue = DispatchQueue.main, label: String = "MXAsyncTaskQueue-" + MXTools.generateSecret()) {
        dispatchGroup = DispatchGroup()
        dispatchGroupQueue = DispatchQueue(label: label)
        self.dispatchQueue = dispatchQueue
    }
    
    /// Schedule a new task.
    ///
    /// Call the passed `taskCompleted` block when the task is done.
    /// 
    /// - Parameter block: the task to execute
    public func async(execute block: @escaping (_ completion: @escaping() -> Void) -> Void) {
        dispatchGroupQueue.async {
            // If any, wait for the completion of the previous task
            self.dispatchGroup.wait()
            self.dispatchGroup.enter()
            
            self.dispatchQueue.async {
                block {
                    // Task completed. Next one can start
                    self.dispatchGroup.leave()
                }
            }
        }
    }
}

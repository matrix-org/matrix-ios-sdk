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

public typealias Block<T> = () async throws -> T

/// A serial queue for performing a block of async tasks together
/// before starting the next block of async tasks.
///
/// Swift concurrency treats each `await` as a potential suspension point meaning there is no guarantee that a group of related `await` tasks
/// will be completed in full before another group is started. This is also the reason why `Actor`s are designed for
/// [re-entrancy](https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md#actor-reentrancy).
///
/// The solution to this problem is using serial task queues where work is scheduled, but only executed once all of the previously
/// scheduled tasks have completed. This is an analogous mechanism to using serial `DispatchQueue`s.
public actor MXTaskQueue {
    public enum Error: Swift.Error {
        case valueUnavailable
    }
    
    private var previousTask: Task<Sendable, Swift.Error>?

    
    /// Add block to the queue and await its executing
    ///
    /// This method is analogous to `DispatchQueue.sync`. Executing it will
    /// suspend the calling site until this and all previously scheduled blocks
    /// have completed
    public func sync<T: Sendable>(block: @escaping Block<T>) async throws -> T {
        let task = newTask(for: block) as Task<Sendable, Swift.Error>
        previousTask = task

        guard let value = try await task.value as? T else {
            assertionFailure("Failing to get value of the correct type should not be possible")
            throw Error.valueUnavailable
        }
        previousTask = nil
        return value
    }

    /// Add block to the queue and resume execution immediately
    ///
    /// This method is analogous to `DispatchQueue.async`. Executing it will
    /// resume the calling site immediately, but will execute this block after
    /// all previously scheduled blockes have completed.
    public func async<T: Sendable>(block: @escaping Block<T>) {
        previousTask = newTask(for: block)
    }
    
    private func newTask<T: Sendable>(for block: @escaping Block<T>) -> Task<T, Swift.Error> {
        return .init { [previousTask] in
            // Capture the value of the previous task and await its completion
            let _ = await previousTask?.result
            // Then await the newly added block
            return try await block()
        }
    }
}

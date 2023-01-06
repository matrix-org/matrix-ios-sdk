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

/// A scheduler for blocks of `async` work, that will execute together, before the next scheduled block.
///
/// In Swift's concurrency model, each `await` is a potential suspension point meaning there is no guarantee that a group of related `await` tasks
/// (represented as a parent `Task`), will be completed in full before another group is started. This is also the reason why `Actor`s are designed for
/// [re-entrancy](https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md#actor-reentrancy).

/// To achieve serial `Task` execution, the `MXSerialTaskScheduler` will:
/// - only execute one `Task` at any point in time
/// - multiple additional `Task`s become the scheduler's single "next", executed only after the "current" completes
public actor MXSerialTaskScheduler<T> {
    private var currentTask: Task<T, Error>?
    private var nextTask: Task<T, Error>?
    
    /// Add a block of `async` work to the scheduler.
    ///
    /// If the scheduler is not currently executing any previous task, the block will be executed right away.
    /// Otherwise we schedule "next" execution, if one is not scheduled already, meaning that multiple simultaneous
    /// calls to `add` will only schedule one "next" task.
    public func add(block: @escaping Block<T>) async throws -> T {
        let task = currentOrNextTask(for: block)
        return try await task.value
    }
    
    private func currentOrNextTask(for block: @escaping Block<T>) -> Task<T, Error> {
        if let currentTask = currentTask {
            let task = nextTask ?? Task {
                // Next task needs to await to completion of the currently running task
                let _ = await currentTask.result
                // Only then we can execute the actual work
                return try await execute(block)
            }
            nextTask = task
            return task
        } else {
            let task = Task {
                // Since we do not have any task running we can execute work right away
                try await execute(block)
            }
            currentTask = task
            return task
        }
    }
    
    private func execute<T: Sendable>(_ block: @escaping Block<T>) async throws -> T {
        defer {
            currentTask = nextTask
            nextTask = nil
        }
        return try await block()
    }
}

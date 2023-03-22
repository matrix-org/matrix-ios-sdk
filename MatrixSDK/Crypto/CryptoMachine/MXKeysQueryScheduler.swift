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

/// A schedule of `keys/query` requests that will ensure only one request
/// is in-flight at any given point in time, and all future queries aggregate
/// requested user ids into a single query.
public actor MXKeysQueryScheduler<Response> {
    typealias QueryAction = ([String]) async throws -> Response
    
    struct Query {
        let users: Set<String>
        let task: Task<Response, Error>
        
        func contains(users: Set<String>) -> Bool {
            users.subtracting(self.users).isEmpty
        }
    }
    
    private let queryAction: QueryAction
    private var nextUsers: Set<String>
    
    private var currentQuery: Query?
    private var nextTask: Task<Response, Error>?

    init(queryAction: @escaping QueryAction) {
        self.queryAction = queryAction
        self.nextUsers = []
    }

    /// Query a list of user ids
    ///
    /// If there is no ongoing query, it will be executed right away,
    /// otherwise it will be scheduled for the next available run.
    public func query(users: Set<String>) async throws -> Response {
        log("Querying \(users.count) user(s): \(users) ...")
        
        let task = currentOrNextQuery(users: users)
        return try await task.value
    }

    private func currentOrNextQuery(users: Set<String>) -> Task<Response, Error> {
        if let currentQuery = currentQuery {
            if currentQuery.contains(users: users) {
                log("... query with the same user(s) already running")
                
                return currentQuery.task
                
            } else {
                log("... queueing user(s) for the next query")
                
                nextUsers = nextUsers.union(users)

                let task = nextTask ?? Task {
                    // Next task needs to await to completion of the currently running task
                    let _ = await currentQuery.task.result

                    // At this point the previous query has already changed `self.currentQuery`
                    // to `next`, so we can extract its users to execute
                    let users = self.currentQuery?.users ?? []

                    // Only then we can execute the actual work
                    return try await executeQuery(users: users)
                }
                nextTask = task
                return task
            }

        } else {
            let task = Task {
                // Since we do not have any task running we can execute work right away
                try await executeQuery(users: users)
            }
            currentQuery = Query(users: users, task: task)
            return task
        }
    }

    private func executeQuery(users: Set<String>) async throws -> Response {
        defer {
            if let nextTask = nextTask {
                log("... query for \(users) completed, starting next pending query.")
                currentQuery = Query(users: nextUsers, task: nextTask)
            } else {
                log("... query for \(users) completed, no other queries scheduled.")
                currentQuery = nil
            }
            nextTask = nil
            nextUsers = []
        }
        
        log("... query starting for \(users)")
        return try await queryAction(Array(users))
    }
    
    private func log(_ message: String) {
        MXLog.debug("[MXKeysQueryScheduler]: \(message)")
    }
}

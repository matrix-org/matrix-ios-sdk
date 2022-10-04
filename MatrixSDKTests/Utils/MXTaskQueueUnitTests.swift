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
import XCTest
@testable import MatrixSDK

class MXTaskQueueUnitTests: XCTestCase {
    /// Dummy error that can be thrown by a task
    enum Error: Swift.Error {
        case dummy
    }
    
    /// An operation within or outside of a task used to assert test results
    struct Operation: Hashable {
        enum Kind: String, CaseIterable, CustomStringConvertible {
            case taskStart
            case taskEnd
            case nonTask
            
            var description: String {
                return rawValue
            }
        }
        
        let id: String
        let kind: Kind
    }
    
    /// A timeline of operation that records exact order of execution of individual operations.
    /// It can be used to assert order of operations, or check whether various tasks overap or not.
    actor Timeline {
        struct OperationRecord {
            let operation: Operation
            let time: Int
        }
        
        private var time = 0
        private var values = [Operation: Int]()
        
        /// Get number of recorded operations
        var numberOfOperations: Int {
            return values.count
        }
        
        /// Create a new record for an operation by adding current time
        func record(_ operation: Operation) {
            time += 1
            values[operation] = time
        }
        
        /// Retrieve the order of operation kinds for a specific id
        func operationOrder(for id: String) -> [Operation.Kind] {
            return values
                .filter { $0.key.id == id }
                .sorted { $0.value < $1.value }
                .map { $0.key.kind }
        }
        
        /// Determine whether two different tasks overlap or not
        func overlapsTasks(id1: String, id2: String) -> Bool {
            let start1 = values[.init(id: id1, kind: .taskStart)] ?? 0
            let end1 = values[.init(id: id1, kind: .taskEnd)] ?? 0
            let start2 = values[.init(id: id2, kind: .taskStart)] ?? 0
            let end2 = values[.init(id: id2, kind: .taskEnd)] ?? 0
            
            return !(start1 < end1
                && start2 < end2
                && (end1 < start2 || end2 < start1))
        }
    }
    
    private var timeline: Timeline!
    private var queue: MXTaskQueue!
    
    override func setUp() {
        timeline = Timeline()
        queue = MXTaskQueue()
    }
    
    // MARK: - No queue tests
    
    func test_noQueue_performsAllOperations() async {
        let taskIds = ["A", "B", "C"]
        for id in taskIds {
            let exp = expectation(description: "exp\(id)")
            executeWorkWithoutQueue(id) {
                exp.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 1)
        await XCTAssertAllOperationsPerformed(taskIds)
    }
    
    func test_noQueue_overlapsTasks() async {
        let taskIds = ["A", "B", "C"]
        for id in taskIds {
            let exp = expectation(description: "exp\(id)")
            executeWorkWithoutQueue(id) {
                exp.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 1)
        await XCTAssertTasksOverlap(taskIds)
    }
    
    // MARK: - Sync queue tests
    
    func test_syncQueue_performsAllOperations() async {
        let taskIds = ["A", "B", "C"]
        for id in taskIds {
            let exp = expectation(description: "exp\(id)")
            executeWorkOnSyncQueue(id) {
                exp.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 1)
        await XCTAssertAllOperationsPerformed(taskIds)
    }
    
    func test_syncQueue_doesNotOverlapTasks() async {
        let taskIds = ["A", "B", "C"]
        for id in taskIds {
            let exp = expectation(description: "exp\(id)")
            executeWorkOnSyncQueue(id) {
                exp.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 1)
        await XCTAssertTasksDoNotOverlap(taskIds)
    }
    
    func test_syncQueue_addsNonTaskLast() async {
        let taskIds = ["A", "B", "C"]
        for id in taskIds {
            let exp = expectation(description: "exp\(id)")
            executeWorkOnSyncQueue(id) {
                exp.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 1)
        await XCTAssertOperationOrderEquals(taskIds, order: [.taskStart, .taskEnd, .nonTask])
    }
    
    func test_syncQueue_throwsError() async throws {
        do {
            try await queue.sync {
                throw Error.dummy
            }
            XCTFail("Should not succeed")
        } catch Error.dummy {
            XCTAssert(true)
        } catch {
            XCTFail("Incorrect error type \(error)")
        }
    }
    
    func test_syncQueue_performsDifferentTaskTypes() async throws {
        var results = [Any]()

        try await queue.sync {
            results.append(1)
        }
        try await queue.sync {
            results.append("ABC")
        }
        try await queue.sync {
            results.append(true)
        }

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0] as? Int, 1)
        XCTAssertEqual(results[1] as? String, "ABC")
        XCTAssertEqual(results[2] as? Bool, true)
    }
    
    // MARK: - Async queue tests
    
    func test_asyncQueue_performsAllOperations() async {
        let taskIds = ["A", "B", "C"]
        for id in taskIds {
            let exp = expectation(description: "exp\(id)")
            executeWorkOnAsyncQueue(id) {
                exp.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 1)
        await XCTAssertAllOperationsPerformed(taskIds)
    }
    
    func test_asyncQueue_doesNotOverlapTasks() async {
        let taskIds = ["A", "B", "C"]
        for id in taskIds {
            let exp = expectation(description: "exp\(id)")
            executeWorkOnAsyncQueue(id) {
                exp.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 1)
        await XCTAssertTasksDoNotOverlap(taskIds)
    }
    
    func test_asyncQueue_addsNonTaskBeforeTaskEnd() async {
        let taskIds = ["A", "B", "C"]
        for id in taskIds {
            let exp = expectation(description: "exp\(id)")
            executeWorkOnAsyncQueue(id) {
                exp.fulfill()
            }
        }
        
        await waitForExpectations(timeout: 1)
        
        // For the async variant `nonTask` could happen before or after `taskStart` but
        // always before `taskEnd`. Instead of asserting the entire flow deterministically
        // we assert relative positions
        await XCTAssertOperationOrder(taskIds, first: .taskStart, second: .taskEnd)
        await XCTAssertOperationOrder(taskIds, first: .nonTask, second: .taskEnd)
    }
    
    // MARK: - Execution helpers
    
    /// Performs some long task (e.g. suspending thread) whilst marking start and end
    private func performLongTask(id: String) async {
        await timeline.record(
            .init(id: id, kind: .taskStart)
        )
        
        await doSomeHeavyWork()
        
        await timeline.record(
            .init(id: id, kind: .taskEnd)
        )
    }
    
    /// Performs short task that executes right away
    private func performShortNonTask(id: String) async {
        await timeline.record(
            .init(id: id, kind: .nonTask)
        )
    }
    
    /// Execute long and short task without using any queues, meaning individual async operations can overlap
    private func executeWorkWithoutQueue(_ taskId: String, completion: @escaping () -> Void) {
        randomDetachedTask {
            await self.performLongTask(id: taskId)
            await self.performShortNonTask(id: taskId)
            completion()
        }
    }
    
    /// Execute long and short task using queue synchronously, meaning individual tasks cannot overlap
    private func executeWorkOnSyncQueue(_ taskId: String, completion: @escaping () -> Void) {
        randomDetachedTask {
            try await self.queue.sync {
                await self.performLongTask(id: taskId)
                completion()
            }
            await self.performShortNonTask(id: taskId)
        }
    }
    
    /// Execute long and short task using queue asynchronously, meaning individual tasks cannot overlap
    private func executeWorkOnAsyncQueue(_ taskId: String, completion: @escaping () -> Void) {
        randomDetachedTask {
            await self.queue.async {
                await self.performLongTask(id: taskId)
                completion()
            }
            await self.performShortNonTask(id: taskId)
        }
    }
    
    /// Perform work on detached task with random priority, so that order of tasks is unpredictable
    private func randomDetachedTask(completion: @escaping () async throws -> Void) {
        let priorities: [TaskPriority] = [.high, .medium, .low]
        Task.detached(priority: priorities.randomElement()) {
            try await completion()
        }
    }
    
    // MARK: - Other helpers
    
    private func doSomeHeavyWork(timeInterval: TimeInterval = 0.1) async {
        do {
            try await Task.sleep(nanoseconds: UInt64(timeInterval * 1e9))
        } catch {
            XCTFail("Error sleeping \(error)")
        }
    }
    
    /// Assert that for every task id all operations (task start, task end and non task) are performed
    private func XCTAssertAllOperationsPerformed(_ taskIds: [String], file: StaticString = #file, line: UInt = #line) async {
        let count = await timeline.numberOfOperations
        XCTAssertEqual(count, taskIds.count * Operation.Kind.allCases.count, file: file, line: line)
    }
    
    /// Assert that operations for each task happen in the exact order specified
    private func XCTAssertOperationOrderEquals(_ taskIds: [String], order: [Operation.Kind], file: StaticString = #file, line: UInt = #line) async {
        for id in taskIds {
            let realOrder = await timeline.operationOrder(for: id)
            XCTAssertEqual(realOrder, order, "Order for task \(id) is incorrect", file: file, line: line)
        }
    }
    
    /// Assert that for every task a given operation occurs before another operation
    private func XCTAssertOperationOrder(_ taskIds: [String], first: Operation.Kind, second: Operation.Kind, file: StaticString = #file, line: UInt = #line) async {
        for id in taskIds {
            let realOrder = await timeline.operationOrder(for: id)
            guard let firstIndex = realOrder.firstIndex(of: first), let secondIndex = realOrder.firstIndex(of: second) else {
                XCTFail("Cannot find given operations", file: file, line: line)
                return
            }
            XCTAssertLessThan(firstIndex, secondIndex, "Operation \(first) does not happen before \(second)", file: file, line: line)
        }
    }
    
    /// Assert that the operations of different tasks overlap (i.e. second task starts before the first task finishes)
    private func XCTAssertTasksOverlap(_ taskIds: [String], file: StaticString = #file, line: UInt = #line) async {
        for i in 0 ..< taskIds.count {
            for j in i + 1 ..< taskIds.count {
                let overlapsTasks = await timeline.overlapsTasks(id1: taskIds[i], id2: taskIds[j])
                XCTAssertTrue(overlapsTasks, "Tasks \(taskIds[i]) and \(taskIds[j]) do not overlap when they should", file: file, line: line)
            }
        }
    }
    
    /// Assert that the operations of different tasks do not overlap (i.e. second task does not start until the firs task has finished)
    private func XCTAssertTasksDoNotOverlap(_ taskIds: [String], file: StaticString = #file, line: UInt = #line) async {
        for i in 0 ..< taskIds.count {
            for j in i + 1 ..< taskIds.count {
                let overlapsTasks = await timeline.overlapsTasks(id1: taskIds[i], id2: taskIds[j])
                XCTAssertFalse(overlapsTasks, "Tasks \(taskIds[i]) and \(taskIds[j]) overlap when they should not", file: file, line: line)
            }
        }
    }
}

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

class MXTaskSchedulerUnitTests: XCTestCase {
    enum Error: Swift.Error, Equatable {
        case dummy
    }
    
    typealias DataVersion = Int
    
    /// A worker that performs some fictional heavy work (... sleep), each time incrementing
    /// data version to spy on the amount of work done.
    /// Each work will also log the `start` and `end` point to test for concurrent access.
    actor HeavyWorkerStub {
        /// A start or end event of processing a particular data version
        struct Event: Equatable, CustomStringConvertible {
            enum EventType: String, CustomStringConvertible {
                case start
                case end
                
                var description: String {
                    return rawValue
                }
            }
            
            let version: DataVersion
            let type: EventType
            
            var description: String {
                return "\(version): \(type)"
            }
        }
        
        private var version = 0
        var history: [Event] = []
        
        /// Fictional heavy work that will increment data version, sleep, and log start/end events
        func heavyWork() async throws -> DataVersion {
            version += 1
            
            let version = version
            history.append(.init(version: version, type: .start))
            try await Task.sleep(nanoseconds: 1_000_000)
            history.append(.init(version: version, type: .end))
            
            return version
        }
    }
    
    private var worker: HeavyWorkerStub!
    private var scheduler: MXSerialTaskScheduler<DataVersion>!
    
    override func setUp() {
        worker = HeavyWorkerStub()
        scheduler = MXSerialTaskScheduler()
    }
    
    // MARK: - Helpers
    
    /// Schedule heavy work on a detached task, meaning that multiple threads can simultaneously
    /// schedule work.
    private func scheduleHeavyWork(completion: @escaping (DataVersion) -> Void) {
        Task.detached {
            let result = try await self.scheduler.add {
                try await self.worker.heavyWork()
            }
            completion(result)
        }
    }
    
    private func scheduleFailingWork(completion: @escaping (Swift.Error) -> Void) {
        Task.detached {
            do {
                let _ = try await self.scheduler.add {
                    throw Error.dummy
                }
            } catch {
                completion(error)
            }
        }
    }
    
    // MARK: - Tests
    
    func test_singleTask_executedImmediately() async throws {
        let exp = expectation(description: "exp")
        scheduleHeavyWork { version in
            XCTAssertEqual(version, 1)
            exp.fulfill()
        }

        await waitForExpectations(timeout: 1)
        
        await XCTAssertEventHistory([
            .init(version: 1, type: .start),
            .init(version: 1, type: .end),
        ])
    }

    func test_secondTask_executedAfterFirstSucceeds() async throws {
        let exp = expectation(description: "exp")
        exp.expectedFulfillmentCount = 2
        
        scheduleHeavyWork { version in
            XCTAssertEqual(version, 1)
            exp.fulfill()
        }
        
        scheduleHeavyWork { version in
            XCTAssertEqual(version, 2)
            exp.fulfill()
        }

        await waitForExpectations(timeout: 1)
        
        await XCTAssertEventHistory([
            .init(version: 1, type: .start),
            .init(version: 1, type: .end),
            .init(version: 2, type: .start),
            .init(version: 2, type: .end),
        ])
    }

    func test_multipleTasksScheduledSimultaneously_executeOnlyOnce() async throws {
        let exp = expectation(description: "exp")
        exp.expectedFulfillmentCount = 1 + 10

        scheduleHeavyWork { version in
            XCTAssertEqual(version, 1)
            exp.fulfill()
        }
        
        // No matter how many tasks we schedule as pending, the work
        // is only performed once and the each recieve data version `2`
        for _ in 0 ..< 10 {
            scheduleHeavyWork { version in
                XCTAssertEqual(version, 2)
                exp.fulfill()
            }
        }

        await waitForExpectations(timeout: 1)

        // History too reflects that the heavy work was only executed twice:
        // the first task got version `1`, the 10 remaining ones got `2`
        let history = await worker.history
        XCTAssertEqual(history, [
            .init(version: 1, type: .start),
            .init(version: 1, type: .end),
            .init(version: 2, type: .start),
            .init(version: 2, type: .end),
        ])
    }
    
    func test_schedulerContinuesExecutingNext() async throws {
        let exp = expectation(description: "exp")
        exp.expectedFulfillmentCount = 3
        
        scheduleHeavyWork { version in
            XCTAssertEqual(version, 1)
            exp.fulfill()
        
            // As soon as the first task completes and next task becomes the current task
            // we schedule another work, so once again we will have a next task scheduled
            // that brings data version to `3`
            self.scheduleHeavyWork { version in
                XCTAssertEqual(version, 3)
                exp.fulfill()
            }
        }
        
        scheduleHeavyWork { version in
            XCTAssertEqual(version, 2)
            exp.fulfill()
        }

        await waitForExpectations(timeout: 1)
        
        await XCTAssertEventHistory([
            .init(version: 1, type: .start),
            .init(version: 1, type: .end),
            .init(version: 2, type: .start),
            .init(version: 2, type: .end),
            .init(version: 3, type: .start),
            .init(version: 3, type: .end),
        ])
    }
    
    func test_executeNewTaskImmediately_wheneverClearSchedule() async throws {
        // First task is executed right away
        var exp = expectation(description: "exp")
        exp.expectedFulfillmentCount = 1
        
        scheduleHeavyWork { version in
            XCTAssertEqual(version, 1)
            exp.fulfill()
        }

        await waitForExpectations(timeout: 1)

        // First task completed (and nothing else was scheduled), so the schedule
        // is clear again and we can execute some task right away
        exp = expectation(description: "exp")
        exp.expectedFulfillmentCount = 3
        
        scheduleHeavyWork { version in
            XCTAssertEqual(version, 2)
            exp.fulfill()
        }
        
        scheduleHeavyWork { version in
            XCTAssertEqual(version, 3)
            exp.fulfill()
        }
        
        scheduleHeavyWork { version in
            XCTAssertEqual(version, 3)
            exp.fulfill()
        }

        await waitForExpectations(timeout: 1)
        
        // We await once again the completion of all scheduled tasks and schedule
        // a few more
        exp = expectation(description: "exp")
        exp.expectedFulfillmentCount = 3
        
        scheduleHeavyWork { version in
            XCTAssertEqual(version, 4)
            exp.fulfill()
        }
        
        scheduleHeavyWork { version in
            XCTAssertEqual(version, 5)
            exp.fulfill()
        }
        
        scheduleHeavyWork { version in
            XCTAssertEqual(version, 5)
            exp.fulfill()
        }

        await waitForExpectations(timeout: 1)
        
        // The total history reflects the fact that despite scheduling 7 tasks,
        // the work was only executed 5 times
        await XCTAssertEventHistory([
            .init(version: 1, type: .start),
            .init(version: 1, type: .end),
            .init(version: 2, type: .start),
            .init(version: 2, type: .end),
            .init(version: 3, type: .start),
            .init(version: 3, type: .end),
            .init(version: 4, type: .start),
            .init(version: 4, type: .end),
            .init(version: 5, type: .start),
            .init(version: 5, type: .end),
        ])
    }
    
    func test_task_executesAfterSeveralFailures() async throws {
        var exp = expectation(description: "exp")
        scheduleFailingWork { error in
            XCTAssertEqual(error as? Error, Error.dummy)
            exp.fulfill()
        }
        
        await waitForExpectations(timeout: 1)
        
        exp = expectation(description: "exp")
        scheduleFailingWork { error in
            XCTAssertEqual(error as? Error, Error.dummy)
            exp.fulfill()
        }

        await waitForExpectations(timeout: 1)

        exp = expectation(description: "exp")
        scheduleFailingWork { error in
            XCTAssertEqual(error as? Error, Error.dummy)
            exp.fulfill()
        }

        await waitForExpectations(timeout: 1)
        
        exp = expectation(description: "exp")
        scheduleHeavyWork { version in
            XCTAssertEqual(version, 1)
            exp.fulfill()
        }

        await waitForExpectations(timeout: 1)
        
        await XCTAssertEventHistory([
            .init(version: 1, type: .start),
            .init(version: 1, type: .end),
        ])
    }
    
    // MARK: - Assertion helpers
    
    private func XCTAssertEventHistory(_ expected: [HeavyWorkerStub.Event], file: StaticString = #file, line: UInt = #line) async {
        let history = await worker.history
        XCTAssertEqual(history, expected, file: file, line: line)
    }
}

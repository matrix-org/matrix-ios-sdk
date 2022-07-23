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

import XCTest

class MXAsyncTaskQueueUnitTests: XCTestCase {

    /// Check that tasks and async tasks are run
    func test() throws {
        let expectation = self.expectation(description: "test")
        var result = ""
        
        let asyncTaskQueue = MXAsyncTaskQueue(dispatchQueue: DispatchQueue(label: "MXAsyncTaskQueueTests"))
                
        asyncTaskQueue.async { taskCompleted in
            Thread.sleep(forTimeInterval: 0.5)
            result = result + "1"
            taskCompleted()
        }
        asyncTaskQueue.async { taskCompleted in
            // True async task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                result = result + "2"
                taskCompleted()
            }
        }
        asyncTaskQueue.async { taskCompleted in
            Thread.sleep(forTimeInterval: 0.01)
            result = result + "3"
            taskCompleted()
        }
        
        asyncTaskQueue.async { _ in
            XCTAssertEqual(result, "123")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1)
    }
}

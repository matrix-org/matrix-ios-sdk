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

@testable import MatrixSDK

class MXBackgroundTaskUnitTests: XCTestCase {
    
    private enum Constants {
        static let bgTaskName: String = "test"
    }
    
    func testInitAndStop() {
        let bgModeHandler = MXUIKitBackgroundModeHandler {
            return MockApplication()
        }
        guard let task = bgModeHandler.startBackgroundTask(withName: Constants.bgTaskName) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        
        XCTAssertEqual(task.name, Constants.bgTaskName, "Task name should be persisted")
        XCTAssertFalse(task.isReusable, "Task should be not reusable by default")
        XCTAssertTrue(task.isRunning, "Task should be running")
        
        task.stop()
        
        XCTAssertFalse(task.isRunning, "Task should be stopped")
    }
    
    func testNotReusableInit() {
        let bgModeHandler = MXUIKitBackgroundModeHandler {
            return MockApplication()
        }
        
        //  create two not reusable task with the same name
        guard let task1 = bgModeHandler.startBackgroundTask(withName: Constants.bgTaskName),
              let task2 = bgModeHandler.startBackgroundTask(withName: Constants.bgTaskName) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        
        //  task1 & task2 should be different instances
        XCTAssertNotEqual(Unmanaged.passUnretained(task1).toOpaque(),
                          Unmanaged.passUnretained(task2).toOpaque(),
                          "Handler should create different tasks when reusability disabled")
    }
    
    func testReusableInit() {
        let bgModeHandler = MXUIKitBackgroundModeHandler {
            return MockApplication()
        }
        
        //  create two reusable task with the same name
        guard let task1 = bgModeHandler.startBackgroundTask(withName: Constants.bgTaskName, reusable: true),
              let task2 = bgModeHandler.startBackgroundTask(withName: Constants.bgTaskName, reusable: true) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        
        //  task1 and task2 should be the same instance
        XCTAssertEqual(Unmanaged.passUnretained(task1).toOpaque(),
                       Unmanaged.passUnretained(task2).toOpaque(),
                       "Handler should create different tasks when reusability disabled")
        
        XCTAssertEqual(task1.name, Constants.bgTaskName, "Task name should be persisted")
        XCTAssertTrue(task1.isReusable, "Task should be reusable")
        XCTAssertTrue(task1.isRunning, "Task should be running")
    }
    
    func testMultipleStops() {
        let bgModeHandler = MXUIKitBackgroundModeHandler {
            return MockApplication()
        }
        
        //  create two reusable task with the same name
        guard let task = bgModeHandler.startBackgroundTask(withName: Constants.bgTaskName, reusable: true),
              let _ = bgModeHandler.startBackgroundTask(withName: Constants.bgTaskName, reusable: true) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        
        XCTAssertTrue(task.isRunning, "Task should be running")
        
        task.stop()
        
        XCTAssertTrue(task.isRunning, "Task should be still running after one stop call")
        
        task.stop()
        
        XCTAssertFalse(task.isRunning, "Task should be stopped after two stop calls")
    }
    
    func testNotValidReuse() {
        let bgModeHandler = MXUIKitBackgroundModeHandler {
            return MockApplication()
        }
        
        //  create two reusable task with the same name
        guard let task = bgModeHandler.startBackgroundTask(withName: Constants.bgTaskName, reusable: true) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        
        XCTAssertTrue(task.isRunning, "Task should be running")
        
        task.stop()
        
        XCTAssertFalse(task.isRunning, "Task should be stopped after stop")
        
        task.reuse()
        
        XCTAssertFalse(task.isRunning, "Task should be stopped after one stop call, even if reuse is called after")
    }
    
    func testValidReuse() {
        let bgModeHandler = MXUIKitBackgroundModeHandler {
            return MockApplication()
        }
        
        //  create two reusable task with the same name
        guard let task = bgModeHandler.startBackgroundTask(withName: Constants.bgTaskName, reusable: true) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        
        XCTAssertTrue(task.isRunning, "Task should be running")
        
        task.reuse()
        
        XCTAssertTrue(task.isRunning, "Task should be still running")
        
        task.stop()
        
        XCTAssertTrue(task.isRunning, "Task should be still running after one stop call")
        
        task.stop()
        
        XCTAssertFalse(task.isRunning, "Task should be stopped after two stop calls")
    }
    
}

fileprivate class MockApplication: MXApplicationProtocol {
    
    private static var bgTaskIdentifier: Int = 0
    
    private var bgTasks: [UIBackgroundTaskIdentifier: Bool] = [:]
    
    func beginBackgroundTask(expirationHandler handler: (() -> Void)? = nil) -> UIBackgroundTaskIdentifier {
        return beginBackgroundTask(withName: nil, expirationHandler: handler)
    }
    
    func beginBackgroundTask(withName taskName: String?, expirationHandler handler: (() -> Void)? = nil) -> UIBackgroundTaskIdentifier {
        Self.bgTaskIdentifier += 1
        
        let identifier = UIBackgroundTaskIdentifier(rawValue: Self.bgTaskIdentifier)
        bgTasks[identifier] = true
        return identifier
    }
    
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        bgTasks.removeValue(forKey: identifier)
    }
    
}

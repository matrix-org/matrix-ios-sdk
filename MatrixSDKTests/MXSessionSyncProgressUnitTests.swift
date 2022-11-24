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
import MatrixSDK

class MXSessionSyncProgressUnitTests: XCTestCase {
    class SpyDelegate: MXSessionSyncProgressDelegate {
        var state: MXSessionSyncState?
        func sessionDidUpdateSyncState(_ state: MXSessionSyncState) {
            self.state = state
        }
    }
    
    var delegate: SpyDelegate!
    var progress: MXSessionSyncProgress!
    override func setUp() {
        delegate = SpyDelegate()
        progress = MXSessionSyncProgress()
        progress.delegate = delegate
    }
    
    func testIncrementsSyncAttempt() {
        XCTAssertNil(delegate.state)
        
        progress.incrementSyncAttempt()
        XCTAssertIsNthSyncingAttempt(1, state: delegate.state)
        
        progress.incrementSyncAttempt()
        XCTAssertIsNthSyncingAttempt(2, state: delegate.state)
        
        progress.incrementSyncAttempt()
        XCTAssertIsNthSyncingAttempt(3, state: delegate.state)
    }
    
    func testUpdatesProcessingProgressForMultiplePhases() {
        XCTAssertNil(delegate.state)
        
        progress.updateProcessingProgress(0, forPhase: .syncResponse)
        XCTAssertProcessingProgress(0, state: delegate.state)
        
        // Sync response is one of 2 possible phases, so its progress contributes 50% to the overal progress
        progress.updateProcessingProgress(0.5, forPhase: .syncResponse)
        XCTAssertProcessingProgress(0.25, state: delegate.state)
        
        // Reporting progress for next phase assumes the previous phase has completed,
        progress.updateProcessingProgress(0.5, forPhase: .roomSummaries)
        XCTAssertProcessingProgress(0.75, state: delegate.state)
        
        // Full progress for the last phase means the overal progres is complete as well
        progress.updateProcessingProgress(1, forPhase: .roomSummaries)
        XCTAssertProcessingProgress(1, state: delegate.state)
    }
    
    func testIgnoresSyncAttemptWhenProcessing() {
        progress.incrementSyncAttempt()
        XCTAssertIsNthSyncingAttempt(1, state: delegate.state)
        
        progress.updateProcessingProgress(0, forPhase: .syncResponse)
        XCTAssertProcessingProgress(0, state: delegate.state)
        
        progress.incrementSyncAttempt()
        XCTAssertProcessingProgress(0, state: delegate.state)
    }
    
    // MARK: - Assertion helpers
    
    private func XCTAssertIsNthSyncingAttempt(_ expectedAttempt: Int, state: MXSessionSyncState?, file: StaticString = #file, line: UInt = #line) {
        if case .serverSyncing(attempt: let attempt) = state {
            XCTAssertEqual(attempt, expectedAttempt, file: file, line: line)
        } else if let state = state {
            XCTFail("Unexpected state \(state)", file: file, line: line)
        } else {
            XCTFail("State is nil", file: file, line: line)
        }
    }
    
    private func XCTAssertProcessingProgress(_ expectedProgress: Double, state: MXSessionSyncState?, file: StaticString = #file, line: UInt = #line) {
        if case .processingResponse(progress: let progress) = state {
            XCTAssertEqual(progress, expectedProgress, file: file, line: line)
        } else if let state = state {
            XCTFail("Unexpected state \(state)", file: file, line: line)
        } else {
            XCTFail("State is nil", file: file, line: line)
        }
    }
}

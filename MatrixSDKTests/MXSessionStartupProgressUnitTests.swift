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

class MXSessionStartupProgressUnitTests: XCTestCase {
    class SpyDelegate: MXSessionStartupProgressDelegate {
        var stage: MXSessionStartupStage?
        func sessionDidUpdateStartupStage(_ stage: MXSessionStartupStage) {
            self.stage = stage
        }
    }
    
    var delegate: SpyDelegate!
    var progress: MXSessionStartupProgress!
    override func setUp() {
        delegate = SpyDelegate()
        progress = MXSessionStartupProgress()
        progress.delegate = delegate
    }
    
    func testIncrementsSyncAttempt() {
        XCTAssertNil(delegate.stage)
        
        progress.incrementSyncAttempt()
        XCTAssertIsNthSyncingAttempt(1, stage: delegate.stage)
        
        progress.incrementSyncAttempt()
        XCTAssertIsNthSyncingAttempt(2, stage: delegate.stage)
        
        progress.incrementSyncAttempt()
        XCTAssertIsNthSyncingAttempt(3, stage: delegate.stage)
    }
    
    func testUpdatesProcessingProgressForMultiplePhases() {
        XCTAssertNil(delegate.stage)
        
        progress.updateProcessingProgress(0, forPhase: .syncResponse)
        XCTAssertProcessingProgress(0, stage: delegate.stage)
        
        // Sync response is one of 2 possible phases, so its progress contributes 50% to the overal progress
        progress.updateProcessingProgress(0.5, forPhase: .syncResponse)
        XCTAssertProcessingProgress(0.25, stage: delegate.stage)
        
        // Reporting progress for next phase assumes the previous phase has completed,
        progress.updateProcessingProgress(0.5, forPhase: .roomSummaries)
        XCTAssertProcessingProgress(0.75, stage: delegate.stage)
        
        // Full progress for the last phase means the overal progres is complete as well
        progress.updateProcessingProgress(1, forPhase: .roomSummaries)
        XCTAssertProcessingProgress(1, stage: delegate.stage)
    }
    
    func testIgnoresSyncAttemptWhenProcessing() {
        progress.incrementSyncAttempt()
        XCTAssertIsNthSyncingAttempt(1, stage: delegate.stage)
        
        progress.updateProcessingProgress(0, forPhase: .syncResponse)
        XCTAssertProcessingProgress(0, stage: delegate.stage)
        
        progress.incrementSyncAttempt()
        XCTAssertProcessingProgress(0, stage: delegate.stage)
    }
    
    // MARK: - Assertion helpers
    
    private func XCTAssertIsNthSyncingAttempt(_ expectedAttempt: Int, stage: MXSessionStartupStage?, file: StaticString = #file, line: UInt = #line) {
        if case .serverSyncing(attempt: let attempt) = stage {
            XCTAssertEqual(attempt, expectedAttempt, file: file, line: line)
        } else if let stage = stage {
            XCTFail("Unexpected stage \(stage)", file: file, line: line)
        } else {
            XCTFail("stage is nil", file: file, line: line)
        }
    }
    
    private func XCTAssertProcessingProgress(_ expectedProgress: Double, stage: MXSessionStartupStage?, file: StaticString = #file, line: UInt = #line) {
        if case .processingResponse(progress: let progress) = stage {
            XCTAssertEqual(progress, expectedProgress, file: file, line: line)
        } else if let stage = stage {
            XCTFail("Unexpected stage \(stage)", file: file, line: line)
        } else {
            XCTFail("stage is nil", file: file, line: line)
        }
    }
}

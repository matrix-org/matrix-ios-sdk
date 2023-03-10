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
        var state: MXSessionStartupProgress.State!
        func sessionDidUpdateStartupProgress(state: MXSessionStartupProgress.State) {
            self.state = state
        }
    }
    
    var delegate: SpyDelegate!
    var progress: MXSessionStartupProgress!
    override func setUp() {
        delegate = SpyDelegate()
        progress = MXSessionStartupProgress()
        progress.delegate = delegate
    }
    
    // MARK: - updateProgressForStage
    
    func test_updateProgress_storeMigration_isHalfOfTotalProgress() {
        progress.updateProgressForStage(.storeMigration, progress: 0)
        XCTAssertEqual(delegate.state.progress, 0)
        
        progress.updateProgressForStage(.storeMigration, progress: 0.5)
        XCTAssertEqual(delegate.state.progress, 0.25)
        
        progress.updateProgressForStage(.storeMigration, progress: 1)
        XCTAssertEqual(delegate.state.progress, 0.5)
    }
    
    func test_updateProgress_serverSyncingWithoutMigration_isZero() {
        progress.updateProgressForStage(.serverSyncing, progress: 0)
        XCTAssertEqual(delegate.state.progress, 0)
    }
    
    func test_updateProgress_serverSyncingAfterMigration_isHalfOfTotalProgress() {
        progress.updateProgressForStage(.storeMigration, progress: 0)
        progress.updateProgressForStage(.serverSyncing, progress: 0)
        XCTAssertEqual(delegate.state.progress, 0.5)
    }
    
    func test_updateProgress_repeatedServerSyncing_showsDelayWarning() {
        progress.updateProgressForStage(.serverSyncing, progress: 0)
        XCTAssertFalse(delegate.state.showDelayWarning)
        
        progress.updateProgressForStage(.serverSyncing, progress: 0)
        XCTAssertTrue(delegate.state.showDelayWarning)
        
        progress.updateProgressForStage(.serverSyncing, progress: 0)
        progress.updateProgressForStage(.serverSyncing, progress: 0)
        XCTAssertTrue(delegate.state.showDelayWarning)
    }
    
    func test_updateProgress_processingResponseWithoutMigration_isEntireProgress() {
        progress.updateProgressForStage(.processingResponse, progress: 0)
        XCTAssertEqual(delegate.state.progress, 0)
        
        progress.updateProgressForStage(.processingResponse, progress: 0.5)
        XCTAssertEqual(delegate.state.progress, 0.5)
        
        progress.updateProgressForStage(.processingResponse, progress: 1)
        XCTAssertEqual(delegate.state.progress, 1)
    }
    
    func test_updateProgress_processingResponseAfterMigration_isHalfOfTotalProgress() {
        progress.updateProgressForStage(.storeMigration, progress: 0)
        
        progress.updateProgressForStage(.processingResponse, progress: 0)
        XCTAssertEqual(delegate.state.progress, 0.5)
        
        progress.updateProgressForStage(.processingResponse, progress: 0.5)
        XCTAssertEqual(delegate.state.progress, 0.75)
        
        progress.updateProgressForStage(.processingResponse, progress: 1)
        XCTAssertEqual(delegate.state.progress, 1)
    }
    
    // MARK: - overalProgressForStep
    
    private func overallProgress(step: Int, count: Int, progress: Double) -> Double {
        self.progress.overallProgressForStep(step, totalCount: count, progress: progress)
    }
    
    func test_overallProgressForStep_oneStep() {
        XCTAssertEqual(overallProgress(step: 0, count: 1, progress: 0), 0)
        XCTAssertEqual(overallProgress(step: 0, count: 1, progress: 0.5), 0.5)
        XCTAssertEqual(overallProgress(step: 0, count: 1, progress: 1), 1)
    }
    
    func test_overallProgress_twoSteps() {
        XCTAssertEqual(overallProgress(step: 0, count: 2, progress: 0), 0)
        XCTAssertEqual(overallProgress(step: 0, count: 2, progress: 0.5), 0.25)
        XCTAssertEqual(overallProgress(step: 0, count: 2, progress: 1), 0.5)
        
        XCTAssertEqual(overallProgress(step: 1, count: 2, progress: 0), 0.5)
        XCTAssertEqual(overallProgress(step: 1, count: 2, progress: 0.5), 0.75)
        XCTAssertEqual(overallProgress(step: 1, count: 2, progress: 1), 1)
    }
    
    func test_overallProgress_tenSteps() {
        XCTAssertEqual(overallProgress(step: 0, count: 10, progress: 0), 0)
        XCTAssertEqual(overallProgress(step: 0, count: 10, progress: 1), 0.1)
        
        XCTAssertEqual(overallProgress(step: 3, count: 10, progress: 0.5), 0.35)
        
        XCTAssertEqual(overallProgress(step: 4, count: 10, progress: 1), 0.5)
        
        XCTAssertEqual(overallProgress(step: 7, count: 10, progress: 0.25), 0.725)
        
        XCTAssertEqual(overallProgress(step: 9, count: 10, progress: 1), 1)
    }
}

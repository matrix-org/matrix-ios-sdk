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

/// Different stages of starting up a session that may complete
/// in non-trivial amount of time. These stages can be observed
/// and used to update the user interface during session loading.
public enum MXSessionStartupStage {
    
    /// Migrating data to a new store version
    case migratingData(progress: Double)
    
    /// Syncing with the server as Nth attempt
    case serverSyncing(attempt: Int)
    
    /// Processing server response
    case processingResponse(progress: Double)
    
    var isSyncing: Bool {
        guard case .serverSyncing = self else {
            return false
        }
        return true
    }
}

/// Delegate that recieves stage updates
public protocol MXSessionStartupProgressDelegate: AnyObject {
    func sessionDidUpdateStartupStage(_ stage: MXSessionStartupStage)
}

/// Distinct phases of the `processingResponse` stage that report
/// their own local progress separately and complete in a given order
@objc public enum MXSessionProcessingResponsePhase: Int, CaseIterable {
    
    /// Processing the response from the server
    case syncResponse
    
    /// Updating room summaries
    case roomSummaries
}

/// `MXSessionStartupProgress` tracks individual stages and per-stage progress
/// during a session startup, where the application may be blocking user interactions.
@objc public class MXSessionStartupProgress: NSObject {
    private var syncAttempts = 0
    private var stage: MXSessionStartupStage? {
        didSet {
            if let state = stage {
                delegate?.sessionDidUpdateStartupStage(state)
            }
        }
    }
    
    public weak var delegate: MXSessionStartupProgressDelegate? {
        didSet {
            if let state = stage {
                delegate?.sessionDidUpdateStartupStage(state)
            }
        }
    }
    
    /// Update the progress of the `migratingData` stage
    @objc public func updateMigrationProgress(_ progress: Double) {
        stage = .migratingData(progress: progress)
    }
    
    /// Increment the total number of sync attempts during the `serverSyncing` stage
    @objc public func incrementSyncAttempt() {
        guard stage == nil || stage?.isSyncing == true else {
            return
        }
        
        syncAttempts += 1
        stage = .serverSyncing(attempt: syncAttempts)
    }
    
    /// Update the local progress of a specific phase within `processingResponse`
    ///
    /// The overal progress will be computed and reported automatically
    @objc public func updateProcessingProgress(_ progress: Double, forPhase phase: MXSessionProcessingResponsePhase) {
        let totalPhases = Double(MXSessionProcessingResponsePhase.allCases.count)
        let currentPhaseProgress = progress / totalPhases
        let previousPhasesProgress = Double(phase.rawValue) / totalPhases
        let totalProgress = previousPhasesProgress + currentPhaseProgress
        
        stage = .processingResponse(progress: totalProgress)
    }
}

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

/// Represents all possible states that a sync can be in
public enum MXSessionSyncState {
    
    /// Syncing with the server as Nth attempt
    case serverSyncing(attempt: Int)
    
    /// Processing server response with 0.0 - 1.0 completed
    case processingResponse(progress: Double)
    
    var isSyncing: Bool {
        guard case .serverSyncing = self else {
            return false
        }
        return true
    }
}

/// Delegate that recieves sync state updates
public protocol MXSessionSyncProgressDelegate: AnyObject {
    func sessionDidUpdateSyncState(_ state: MXSessionSyncState)
}

/// Distinct phases of the `processingResponse` state that report
/// their own local progress separately and complete in a given order
@objc public enum MXSessionSyncProcessingPhase: Int, CaseIterable {
    
    /// Processing the response from the server
    case syncResponse
    
    /// Updating room summaries
    case roomSummaries
}

/// `MXSessionSyncProgress` tracks the overal state of sync and reports
/// this state to its delegate
@objcMembers public class MXSessionSyncProgress: NSObject {
    private var syncAttempts = 0
    private var state: MXSessionSyncState? {
        didSet {
            if let state = state {
                delegate?.sessionDidUpdateSyncState(state)
            }
        }
    }
    
    public weak var delegate: MXSessionSyncProgressDelegate? {
        didSet {
            if let state = state {
                delegate?.sessionDidUpdateSyncState(state)
            }
        }
    }
    
    /// Increment the total number of sync attempts
    public func incrementSyncAttempt() {
        guard state == nil || state?.isSyncing == true else {
            return
        }
        
        syncAttempts += 1
        state = .serverSyncing(attempt: syncAttempts)
    }
    
    /// Update the local progress of a specific processing phase
    ///
    /// The overal progress will be computed and reported automatically
    public func updateProcessingProgress(_ progress: Double, forPhase phase: MXSessionSyncProcessingPhase) {
        let totalPhases = Double(MXSessionSyncProcessingPhase.allCases.count)
        let currentPhaseProgress = progress / totalPhases
        let previousPhasesProgress = Double(phase.rawValue) / totalPhases
        let totalProgress = previousPhasesProgress + currentPhaseProgress
        
        state = .processingResponse(progress: totalProgress)
    }
}

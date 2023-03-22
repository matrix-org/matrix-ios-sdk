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
@objc public enum MXSessionStartupStage: Int, CaseIterable {
    
    /// Migrating data to a new store version
    case storeMigration
    
    /// Syncing with the server
    case serverSyncing
    
    /// Processing server response
    case processingResponse
}

/// Delegate that receives progress state updates
public protocol MXSessionStartupProgressDelegate: AnyObject {
    func sessionDidUpdateStartupProgress(state: MXSessionStartupProgress.State)
}

/// `MXSessionStartupProgress` tracks progress for individual stages during a session startup,
///  where the application may be blocking user interactions.
@objc public class MXSessionStartupProgress: NSObject {
    public struct State {
        public let progress: Double
        public let showDelayWarning: Bool
    }
    
    public weak var delegate: MXSessionStartupProgressDelegate? {
        didSet {
            if let state = state {
                delegate?.sessionDidUpdateStartupProgress(state: state)
            }
        }
    }
    
    private var updatedStages = Set<MXSessionStartupStage>()
    private var state: State? {
        didSet {
            if let state = state {
                delegate?.sessionDidUpdateStartupProgress(state: state)
            }
        }
    }
    
    /// Update progress for a given stage as a number between 0.0-1.0
    ///
    /// The update will inform a delegate with a new progress state containing the overall calculated
    /// progress, depending on total number of startup stages.
    @objc public func updateProgressForStage(_ stage: MXSessionStartupStage, progress: Double) {
        switch stage {
        case .storeMigration:
            state = State(
                // Migration contributes to half of the overall progress
                progress: progress / 2,
                showDelayWarning: false
            )
        case .serverSyncing:
            state = State(
                // If we have previously migrated, we start at 0.5, otherwise at 0
                progress: updatedStages.contains(.storeMigration) ? 0.5 : 0,
                // We display delay warning if this is second or higher sync attempt
                showDelayWarning: updatedStages.contains(.serverSyncing)
            )
        case .processingResponse:
            state = State(
                // If we have previously migrated, we start at 0.5, otherwise we take up the entire progress
                progress: updatedStages.contains(.storeMigration) ? 0.5 + progress / 2 : progress,
                showDelayWarning: false
            )
        }
        
        updatedStages.insert(stage)
    }
    
    /// Calculate the overall progress for a given step out of total steps
    @objc public func overallProgressForStep(_ currentStep: Int, totalCount: Int, progress: Double) -> Double {
        guard totalCount > 0 else {
            return 0
        }
        
        let currentStepProgress = progress / Double(totalCount)
        let previousStepProgress = Double(currentStep) / Double(totalCount)
        return previousStepProgress + currentStepProgress
    }
}

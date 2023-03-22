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

/// Class that computes verification state for a request_id by comparing all related events
/// and taking whichever final event (e.g. cancelled, done), when the request is no longer
/// active.
actor MXKeyVerificationStateResolver {
    private let myUserId: String
    private let aggregations: MXAggregations
    private var states: [String: MXKeyVerificationState]
    private let log = MXNamedLog(name: "MXKeyVerificationStateResolver")
    
    init(myUserId: String, aggregations: MXAggregations) {
        self.myUserId = myUserId
        self.aggregations = aggregations
        self.states = [:]
    }
    
    func verificationState(flowId: String, roomId: String) async throws -> MXKeyVerificationState {
        log.debug("->")
        
        if let state = states[flowId] {
            return state
        }
        
        let state = try await resolvedState(flowId: flowId, roomId: roomId)
        states[flowId] = state
        return state
    }
    
    private func resolvedState(flowId: String, roomId: String) async throws -> MXKeyVerificationState {
        log.debug("Resolving state")
        
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            _ = aggregations.referenceEvents(
                forEvent: flowId,
                inRoom: roomId,
                from: nil,
                limit: -1,
                success: { response in
                    guard let self = self else { return }
                    
                    let state = self.resolvedState(for: response.chunk)
                    self.log.debug("Computed state:  \(state)")
                    continuation.resume(returning: state)
                }, failure: { error in
                    self?.log.error("Failed computing state", context: error)
                    continuation.resume(throwing: error)
                }
            )
        }
    }
    
    nonisolated
    private func resolvedState(for events: [MXEvent]) -> MXKeyVerificationState {
        var defaultState = MXKeyVerificationState.transactionStarted
        for event in events {
            switch event.eventType {
            case .keyVerificationCancel:
                let code = event.content["code"] as? String
                if code == MXTransactionCancelCode.user().value {
                    if event.sender == myUserId {
                        return .transactionCancelledByMe
                    } else {
                        return .transactionCancelled
                    }
                } else if code == MXTransactionCancelCode.timeout().value {
                    return .requestExpired
                } else {
                    return .transactionFailed
                }
            case .keyVerificationReady:
                defaultState = .requestReady
            case .keyVerificationDone:
                return .verified
            default:
                continue
            }
        }
        return defaultState
    }
}

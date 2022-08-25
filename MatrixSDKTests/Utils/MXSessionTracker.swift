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

import Foundation

/// A structure that represents a tracked MXSession
struct TrackedMXSession {
    /// A human readable id for the MXSession
    let userDeviceId: String
    
    /// The call stack that instantiated it
    let callStack: [String]
}

/// The singleton that tracks MXSessions life from init(matrixRestClient:) to close()
/// It can detect MXSession leaks that continue to run in background.
class MXSessionTracker {
    
    // MARK: - Public
    
    static let shared = MXSessionTracker()
    
    func trackMXSessions() {
        MXSession.trackOpenMXSessions()
        MXSession.initCloseDelegate = self
    }
    
    var openMXSessionsCount: Int {
        get {
            trackedMXSessions.count
        }
    }
    
    func resetOpenMXSessions() {
        trackedMXSessions.removeAll()
    }
    
    func printOpenMXSessions() {
        for (trackId, trackedMXSession) in trackedMXSessions {
            MXLog.error("MXSession for user is not closed", context: [
                "track_id": trackId,
            ])
            MXLog.debug("MXSession was created from:")
            trackedMXSession.callStack.forEach { call in
                MXLog.debug("    - \(call)")
            }
        }
    }
    
    // MARK: - Private
    
    /// All open sessions
    private var trackedMXSessions = [String: TrackedMXSession]()
    
    func trackMXSession(mxSession: MXSession, callStack: [String]) {
        let trackedMXSession = TrackedMXSession(userDeviceId: mxSession.userDeviceId, callStack: callStack)
        trackedMXSessions.updateValue(trackedMXSession, forKey: mxSession.trackId)
    }
    
    func untrackMXSession(mxSession: MXSession) {
        trackedMXSessions.removeValue(forKey:  mxSession.trackId)
    }
}

extension MXSessionTracker: MXSessionInitCloseDelegate {
    
    func didInit(mxSession: MXSession, callStack: [String]) {
        trackMXSession(mxSession: mxSession, callStack: callStack)
    }
    
    func willClose(mxSession: MXSession) {
        untrackMXSession(mxSession: mxSession)
    }
}


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

// A structure that represents a tracked MXSession
struct TrackedMXSession {
    /// A human readable id for the MXSession
    let userDeviceId: String
    
    /// The call stack that instantiated it
    let callStack: [String]
}


/// An extension to track alive MXSession instances in a static way.
/// A MXSession is considered alive between its init and close.
extension MXSession {
    
    // MARK: - Public
    
    /// Start tracking open MXSession instances.
    @objc
    class func trackOpenMXSessions() {
        // Swizzle init and close methods to track active MXSessions
        swizzleMethods(orignalSelector: #selector(MXSession.init(matrixRestClient:)),
                       swizzledSelector: #selector(MXSession.trackInit(matrixRestClient:)))
        swizzleMethods(orignalSelector: #selector(MXSession.close),
                       swizzledSelector: #selector(MXSession.trackClose))
    }
    
    @objc
    class var openMXSessionsCount: Int {
        get {
            trackedMXSessions.count
        }
    }
    
    /// Reset MXSession instances already tracked.
    @objc
    class func resetOpenMXSessions() {
        trackedMXSessions.removeAll()
    }
    
    /// Print all open MXSession instances.
    @objc
    class func logOpenMXSessions() {
        for (trackId, trackedMXSession) in trackedMXSessions {
            MXLog.error("MXSession(\(trackId)) for user \(trackedMXSession.userDeviceId) is not closed. It was created from:")
            trackedMXSession.callStack.forEach { call in
                MXLog.error("    - \(call)")
            }
        }
    }
    
    // MARK: - Private
    
    // MARK: Properties
    
    /// All open sessions
    private static var trackedMXSessions = Dictionary<String, TrackedMXSession>()

    /// Id that identifies the MXSession instance
    private var trackId: String {
        // Let's use the MXSession pointer to track it
        "\(Unmanaged.passUnretained(self).toOpaque())"
    }

    /// Human readable id
    private var userDeviceId: String {
        get {
            // Manage string properties that are actually optional
            [myUserId, myDeviceId]
                .compactMap { $0 }
                .joined(separator: ":")
        }
    }
    
    
    // MARK: - Swizzling
    
    /// Exchange 2 methods implementations
    /// - Parameters:
    ///   - orignalSelector: the original method
    ///   - swizzledSelector: the replacing method
    private class func swizzleMethods(orignalSelector: Selector, swizzledSelector: Selector) {
        guard
            let originalMethod = class_getInstanceMethod(MXSession.self, orignalSelector),
            let swizzledMethod = class_getInstanceMethod(MXSession.self, swizzledSelector)
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    /// Swizzled version of MXSession.init(matrixRestClient:)
    @objc
    private func trackInit(matrixRestClient: MXRestClient) -> MXSession {
        // Call the original method. Note that implementations are exchanged
        _ = self.trackInit(matrixRestClient: matrixRestClient)
        
        // And keep the call stack that created the session
        let trackedMXSession = TrackedMXSession(userDeviceId: userDeviceId, callStack: Thread.callStackSymbols)
        MXSession.trackedMXSessions.updateValue(trackedMXSession, forKey: self.trackId)

        return self
    }
    
    /// Swizzled version of MXSession.close()
    @objc
    private func trackClose() {
        // Call the original method. Note that implementations are exchanged
        self.trackClose()
        
        MXSession.trackedMXSessions.removeValue(forKey:  self.trackId)
    }
}

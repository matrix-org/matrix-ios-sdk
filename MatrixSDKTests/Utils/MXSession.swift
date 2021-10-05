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


/// Delegate called on MXSession calls
protocol MXSessionInitCloseDelegate {
    func didInit(mxSession: MXSession, callStack: [String])
    func willClose(mxSession: MXSession)
}


/// An extension for reporting calls to `init(matrixRestClient:)` and `close()` on `MXSession` instances
extension MXSession {
    
    // MARK: - Public
    static var initCloseDelegate: MXSessionInitCloseDelegate?
    
    /// Start tracking open MXSession instances.
    class func trackOpenMXSessions() {
        // Swizzle init and close methods to track active MXSessions
        swizzleMethods(originalSelector: #selector(MXSession.init(matrixRestClient:)),
                       swizzledSelector: #selector(MXSession.trackInit(matrixRestClient:)))
        swizzleMethods(originalSelector: #selector(MXSession.close),
                       swizzledSelector: #selector(MXSession.trackClose))
    }
    
    // MARK: - Private
    
    // MARK: Swizzling
    
    /// Exchange 2 methods implementations
    /// - Parameters:
    ///   - orignalSelector: the original method
    ///   - swizzledSelector: the replacing method
    private class func swizzleMethods(originalSelector: Selector, swizzledSelector: Selector) {
        guard
            let originalMethod = class_getInstanceMethod(MXSession.self, originalSelector),
            let swizzledMethod = class_getInstanceMethod(MXSession.self, swizzledSelector)
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    /// Swizzled version of MXSession.init(matrixRestClient:)
    @objc
    private func trackInit(matrixRestClient: MXRestClient) -> MXSession {
        // Call the original method. Note that implementations are exchanged
        _ = self.trackInit(matrixRestClient: matrixRestClient)

        if let initCloseDelegate = MXSession.initCloseDelegate {
            initCloseDelegate.didInit(mxSession: self, callStack: Thread.callStackSymbols)
        }
        return self
    }
    
    /// Swizzled version of MXSession.close()
    @objc
    private func trackClose() {
        if let initCloseDelegate = MXSession.initCloseDelegate {
            initCloseDelegate.willClose(mxSession: self)
        }
        
        // Call the original method. Note that implementations are exchanged
        self.trackClose()
    }
}


extension MXSession {
    /// Id that identifies the MXSession instance
    var trackId: String {
        // Let's use the MXSession pointer to track it
        "\(Unmanaged.passUnretained(self).toOpaque())"
    }
    
    /// Human readable id
    var userDeviceId: String {
        get {
            // Manage string properties that are actually optional
            [myUserId, myDeviceId]
                .compactMap { $0 }
                .joined(separator: ":")
        }
    }
}

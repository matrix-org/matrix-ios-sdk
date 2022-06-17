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
import Network
import AFNetworking

// MARK: - MXNetworkMonitor notification constants
extension MXNetworkMonitor {
    /// Posted each time the reachability changes
    public static let reachabilityDidChange = Notification.Name("MXNetworkMonitorReachabilityDidChange")
}

/// `MXNetworkMonitor` enables to monitor network reachability.
@available(iOS 12.0, *)
@objcMembers
@objc class MXNetworkMonitor: NSObject {
    
    // MARK: - Singleton
    
    static let shared = MXNetworkMonitor()
    
    override private init() {
        super.init()
    }
    
    // MARK: - Private
    
    private var monitor: NWPathMonitor?
    private let processingQueue = DispatchQueue(label: "org.matrix.sdk.MXNetworkMonitor.processingQueue")
    
    // MARK: - Properties
    
    private(set) var isReachable: Bool = false
    
    // MARK: - Public methods
    
    func startMonitoring() {
        guard monitor == nil else {
            MXLog.warning("[MXNetworkMonitor] startMonitoring canceled: already monitoring.")
            return
        }
        monitor = NWPathMonitor()
        monitor?.start(queue: processingQueue)
        monitor?.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            self.isReachable = path.status == .satisfied

            if path.status == .satisfied {
                MXLog.debug("[MXNetworkMonitor] is now online")
            } else {
                MXLog.debug("[MXNetworkMonitor] is offline")
            }
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.reachabilityDidChange, object: self)
            }
        }
        
        // Needed by the SDK
        AFNetworkReachabilityManager.shared().startMonitoring()
    }
    
    func stopMonitoring() {
        monitor?.cancel()
        monitor = nil
        
        // Needed by the SDK
        AFNetworkReachabilityManager.shared().stopMonitoring()
    }
}

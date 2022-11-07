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

#if os(iOS)

import Foundation
import UIKit

@objcMembers
/// This class provide allows to get current UIApplication.State of the app from any thread.
/// It is only useful because UIApplication.shared.applicationState can be called only from the main thread.
public class MXUIKitApplicationStateService: NSObject {
    
    //  MARK: - Properties
    
    private(set) public var applicationState: UIApplication.State
    
    public var backgroundTimeRemaining: TimeInterval {
        get {
            self.sharedApplication?.backgroundTimeRemaining ?? 0
        }
    }
    
    
    //  MARK: - Static Method
    
    static public func readableApplicationState(_ applicationState: UIApplication.State) -> NSString {
        switch applicationState {
            case .active:
                return "active"
            case .inactive:
                return "inactive"
            case .background:
                return "background"
            @unknown default:
                return "unknown"
        }
    }
    
    static public func readableEstimatedBackgroundTimeRemaining(_ backgroundTimeRemaining: TimeInterval) -> NSString {
        if backgroundTimeRemaining == .greatestFiniteMagnitude {
            return "undetermined"
        }
        else {
            return NSString(format: "%.0f seconds", backgroundTimeRemaining)
        }
    }
    
    
    //  MARK: - Method Overrides
    
    public override init() {
        applicationState = .inactive
        super.init()
        
        applicationState = self.sharedApplicationState

        registerApplicationStateChangeNotifications()
    }
    
    
    //  MARK: - Private
    
    private func registerApplicationStateChangeNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(applicationStateDidChange), name: UIApplication.didEnterBackgroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(applicationStateDidChange), name: UIApplication.willEnterForegroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(applicationStateDidChange), name: UIApplication.didFinishLaunchingNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(applicationStateDidChange), name: UIApplication.didBecomeActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(applicationStateDidChange), name: UIApplication.willResignActiveNotification, object: nil)
    }
    
    @objc private func applicationStateDidChange() {
        // We are on the main tread. We can safely use UIApplication.shared.applicationState
        let newApplicationState = self.sharedApplicationState
        
        if newApplicationState != applicationState {
            let applicationStateString = MXUIKitApplicationStateService.readableApplicationState(applicationState)
            let newApplicationStateString = MXUIKitApplicationStateService.readableApplicationState(newApplicationState)
            MXLog.debug("[MXUIKitApplicationStateService] applicationStateDidChange: from \(applicationStateString) to \(newApplicationStateString)")
            
            applicationState = newApplicationState
        }
    }
    
    private var sharedApplication: UIApplication? {
        get {
            let selector = NSSelectorFromString("sharedApplication")
            
            // We cannot use UIApplication.shared from app extensions
            // TODO: Move UIKit related code to a dedicated cocoapod sub spec
            guard UIApplication.responds(to: selector) else {
                return nil
            }
            
            return UIApplication.perform(selector)?.takeUnretainedValue() as? UIApplication
        }
    }
    
    private var sharedApplicationState: UIApplication.State {
        get {
            guard let application = self.sharedApplication else {
                return .inactive
            }

            // Can be only called from the main thread
            assert(Thread.isMainThread, "[MXUIKitApplicationStateService] UIApplication.applicationState called on non-main thread.")
            return application.applicationState
        }
    }
}

#endif

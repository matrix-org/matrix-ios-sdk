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
import AVFoundation

/// Audio output router class
@objcMembers
public class MXiOSAudioOutputRouter: NSObject {
    
    private enum Constants {
        static let loudSpeakersIdentifier: String = "LOUD_SPEAKERS"
        static let loudSpeakersName: String = "Device Speaker"
        static let builtInIdentifier: String = "BUILT_IN"
    }
    
    //  MARK: - Properties
    
    /// Delegate object
    public weak var delegate: MXiOSAudioOutputRouterDelegate?
    
    /// Default route type. Will be `builtIn` for voice calls, `loudSpeakers` for video calls.
    private let defaultRouteType: MXiOSAudioOutputRouteType
    
    /// External device info. First value: flag to indicate an external device exists, second value: name of the external device
    private var allRoutes: [MXiOSAudioOutputRoute] = [] {
        didSet {
            if allRoutes != oldValue {
                delegate?.audioOutputRouter?(didUpdateAvailableRouteTypes: self)
            }
        }
    }
    
    /// Current route type. Listen `audioOutputRouterDidUpdateRoute` delegate methods for changes.
    public private(set) var currentRoute: MXiOSAudioOutputRoute? {
        didSet {
            delegate?.audioOutputRouter?(didUpdateRoute: self)
        }
    }
    
    /// Flag to learn if some external device is connected.
    /// Listen `audioOutputRouterDidUpdateAvailableRouteTypes` delegate method for changes.
    public var isAnyExternalDeviceConnected: Bool {
        return allRoutes.filter({ $0.isExternal }).count > 0
    }
    
    //  MARK: - Public
    
    /// Initializer
    /// - Parameter call: Call object to decide default route type.
    public init(forCall call: MXCall) {
        if call.isVideoCall {
            defaultRouteType = .loudSpeakers
        } else {
            defaultRouteType = .builtIn
        }
        super.init()
        configureOutputPort()
        if currentRoute == nil {
            currentRoute = allRoutes.first(where: { $0.routeType == defaultRouteType })
        }
        startObservingRouteChanges()
    }
    
    /// Available route types
    /// Listen `audioOutputRouterDidUpdateAvailableRouteTypes` delegate method for changes.
    public var availableOutputRoutes: [MXiOSAudioOutputRoute] {
        return allRoutes
    }
    
    /// The route for `builtIn` route type. May be nil for some cases, like when a wired headphones are connected.
    public var builtInRoute: MXiOSAudioOutputRoute? {
        return allRoutes.first(where: { $0.routeType == .builtIn })
    }
    
    /// The route for `loudSpeakers` route type.
    public var loudSpeakersRoute: MXiOSAudioOutputRoute? {
        return allRoutes.first(where: { $0.routeType == .loudSpeakers })
    }
    
    /// Attempt to override route type to given type.
    /// - Parameter route: Desired route. If `nil` passed, then it would fallback to the default route.
    public func changeCurrentRoute(to route: MXiOSAudioOutputRoute?) {
        if let route = route {
            updateRoute(to: route)
        } else if let defaultRoute = allRoutes.first(where: { $0.routeType == defaultRouteType }) {
            updateRoute(to: defaultRoute)
        }
    }
    
    /// Reroute the audio for the current route type.
    public func reroute() {
        changeCurrentRoute(to: currentRoute)
    }
    
    //  MARK: - Private
    
    private func shouldAddLoudSpeakers(to routes: [MXiOSAudioOutputRoute]) -> Bool {
        return routes.first(where: { $0.routeType == .loudSpeakers }) == nil
    }
    
    private func shouldAddBuiltIn(to routes: [MXiOSAudioOutputRoute]) -> Bool {
        return routes.first(where: { $0.routeType == .builtIn }) == nil
            && routes.first(where: { $0.routeType == .externalWired }) == nil
            && defaultRouteType == .builtIn
    }
    
    private func recomputeAllRoutes() {
        var routes = AVAudioSession.sharedInstance().outputRoutes
        if shouldAddLoudSpeakers(to: routes) {
            //  add loudSpeakers route manually
            routes.append(MXiOSAudioOutputRoute(identifier: Constants.loudSpeakersIdentifier,
                                             routeType: .loudSpeakers,
                                             name: Constants.loudSpeakersName))
        }
        if shouldAddBuiltIn(to: routes) {
            //  add builtIn route manually
            routes.append(MXiOSAudioOutputRoute(identifier: Constants.builtInIdentifier,
                                             routeType: .builtIn,
                                             name: UIDevice.current.localizedModel))
        }
        
        routes.sort { route1, route2 in
            return route1.routeType.rawValue < route2.routeType.rawValue
        }
        
        allRoutes = routes
    }
    
    private func configureOutputPort() {
        recomputeAllRoutes()
        if isAnyExternalDeviceConnected {
            if let wired = allRoutes.first(where: { $0.routeType == .externalWired }) {
                updateRoute(to: wired)
            } else if let bluetooth = allRoutes.first(where: { $0.routeType == .externalBluetooth }) {
                updateRoute(to: bluetooth)
            } else if let car = allRoutes.first(where: { $0.routeType == .externalCar }) {
                updateRoute(to: car)
            }
        } else if let defaultRoute = allRoutes.first(where: { $0.routeType == defaultRouteType }) {
            updateRoute(to: defaultRoute)
        }
    }
    
    private func updateRoute(to route: MXiOSAudioOutputRoute) {
        MXLog.debug("[MXiOSAudioOutputRouter] updateRoute: to: \(route)")
        
        do {
            switch route.routeType {
            case .loudSpeakers:
                if AVAudioSession.sharedInstance().category != .playAndRecord
                    || AVAudioSession.sharedInstance().categoryOptions != [.allowBluetooth, .allowBluetoothA2DP] {
                    try AVAudioSession.sharedInstance().setCategory(.playAndRecord,
                                                                    options: [.allowBluetooth, .allowBluetoothA2DP])
                }
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                try AVAudioSession.sharedInstance().setPreferredInput(nil)
            case .builtIn:
                if AVAudioSession.sharedInstance().category != .playAndRecord
                    || AVAudioSession.sharedInstance().categoryOptions != .init(rawValue: 0) {
                    try AVAudioSession.sharedInstance().setCategory(.playAndRecord,
                                                                    options: .init(rawValue: 0))
                }
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
                try AVAudioSession.sharedInstance().setPreferredInput(nil)
            default:
                if AVAudioSession.sharedInstance().category != .playAndRecord
                    || AVAudioSession.sharedInstance().categoryOptions != [.allowBluetooth, .allowBluetoothA2DP] {
                    try AVAudioSession.sharedInstance().setCategory(.playAndRecord,
                                                                    options: [.allowBluetooth, .allowBluetoothA2DP])
                }
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
                try AVAudioSession.sharedInstance().setPreferredInput(route.port)
            }
            currentRoute = route
        } catch {
            MXLog.error("[MXiOSAudioOutputRouter] updateRoute: routing failed", context: error)
        }
    }

    private func startObservingRouteChanges() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(routeChanged(_:)),
                                               name: AVAudioSession.routeChangeNotification,
                                               object: nil)
    }
    
    private func stopObservingRouteChanges() {
        NotificationCenter.default.removeObserver(self,
                                                  name: AVAudioSession.routeChangeNotification,
                                                  object: nil)
    }
    
    @objc
    private func routeChanged(_ notification: Notification) {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let changeReason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch changeReason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            configureOutputPort()
        default:
            break
        }
    }
    
    deinit {
        stopObservingRouteChanges()
    }
    
}

//  MARK: - AVAudioSession Extension

fileprivate extension AVAudioSession {
    
    var outputRoutes: [MXiOSAudioOutputRoute] {
        return currentRoute.outputs.map({ MXiOSAudioOutputRoute(withPort: $0) })
    }
    
}

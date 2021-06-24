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

@objc
/// Audio output route type
public enum MXAudioOutputRouteType: Int {
    /// the speakers at the top of the screen.
    case builtIn
    /// the speakers at the bottom of the phone
    case loudSpeakers
    /// an external device, like headphones or Bluetooth devices
    case external
}

/// Audio output router delegate
@objc
public protocol MXAudioOutputRouterDelegate: AnyObject {
    /// Delegate method to be called when output route changes, for both user actions and system changes
    /// Check again `routeType` to see the change.
    /// - Parameter router: Router instance
    @objc optional func audioOutputRouter(didUpdateRoute router: MXAudioOutputRouter)
    
    /// Delegate method to be called when available output routes change
    /// Check again `availableOutputRouteTypes` to see the changes.
    /// - Parameter router: Router instance
    @objc optional func audioOutputRouter(didUpdateAvailableRouteTypes router: MXAudioOutputRouter)
}

/// Audio output router class
@objcMembers
public class MXAudioOutputRouter: NSObject {
    
    //  MARK: - Properties
    
    /// Delegate object
    public weak var delegate: MXAudioOutputRouterDelegate?
    
    /// Default route type. Will should be `builtIn` for voice calls, `loudSpeakers` for video calls.
    private let defaultRouteType: MXAudioOutputRouteType
    
    /// Current route type. Listen `audioOutputRouterDidUpdateRoute` delegate methods for changes.
    public private(set) var routeType: MXAudioOutputRouteType {
        didSet {
            delegate?.audioOutputRouter?(didUpdateRoute: self)
        }
    }
    
    /// Flag to learn if some external device is connected. Listen `audioOutputRouterDidUpdateAvailableRouteTypes` delegate method for changes.
    public private(set) var isExternalDeviceConnected: Bool = false {
        didSet {
            if isExternalDeviceConnected != oldValue {
                delegate?.audioOutputRouter?(didUpdateAvailableRouteTypes: self)
            }
        }
    }
    
    /// Name of the external device. Would be nil if not `isExternalDeviceConnected`.
    public var externalDeviceName: String? {
        return AVAudioSession.sharedInstance().externalDeviceName
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
        routeType = defaultRouteType
        super.init()
        configureOutputPort()
        startObservingRouteChanges()
    }
    
    /// Available route types. Listen `audioOutputRouterDidUpdateAvailableRouteTypes` delegate method for changes.
    public var availableOutputRouteTypes: [MXAudioOutputRouteType] {
        if isExternalDeviceConnected {
            return [.builtIn, .loudSpeakers, .external]
        } else {
            return [.builtIn, .loudSpeakers]
        }
    }
    
    /// Attempt to override route type to given type.
    /// - Parameter routeType: Desired route type. `external` is useless if no external device connected, then it would fallback to the default route type.
    public func changeRouteType(to routeType: MXAudioOutputRouteType) {
        switch routeType {
        case .builtIn:
            configureOutputPort(forRouteType: .builtIn)
        case .loudSpeakers:
            configureOutputPort(forRouteType: .loudSpeakers)
        case .external:
            if isExternalDeviceConnected {
                configureOutputPort(forRouteType: .external)
            } else {
                configureOutputPort(forRouteType: defaultRouteType)
            }
        default:
            break
        }
    }
    
    /// Reroute the audio for the current route type.
    public func reroute() {
        changeRouteType(to: routeType)
    }
    
    //  MARK: - Private
    
    private func recomputeIsExternalDeviceConnected() {
        isExternalDeviceConnected = AVAudioSession.sharedInstance().isExternalDeviceConnected
    }
    
    private func configureOutputPort() {
        recomputeIsExternalDeviceConnected()
        if isExternalDeviceConnected {
            configureOutputPort(forRouteType: .external)
        } else {
            configureOutputPort(forRouteType: defaultRouteType)
        }
    }
    
    private func configureOutputPort(forRouteType type: MXAudioOutputRouteType) {
        MXLog.debug("[MXAudioOutputRouter] configureOutputPort: for type: \(type.rawValue)")
        
        switch type {
        case .builtIn:
            MXLog.debug("[MXAudioOutputRouter] configureOutputPort: route output to built-in")
            
            do {
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
                if isExternalDeviceConnected {
                    //  overriding to none is not enough if an external device connected, also set output data source
                    try AVAudioSession.sharedInstance().setMode(.voiceChat)
                    try AVAudioSession.sharedInstance().setOutputDataSource(AVAudioSession.sharedInstance().builtInSpeaker)
                }
                routeType = type
            } catch {
                MXLog.error("[MXAudioOutputRouter] configureOutputPort: routing output to built-in failed: \(error)")
            }
        case .loudSpeakers:
            MXLog.debug("[MXAudioOutputRouter] configureOutputPort: route output to loud speakers")
            
            do {
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                routeType = type
            } catch {
                MXLog.error("[MXAudioOutputRouter] configureOutputPort: routing output to loud speakers failed: \(error)")
            }
        case .external:
            MXLog.debug("[MXAudioOutputRouter] configureOutputPort: route output to external")
            
            do {
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
                routeType = type
            } catch {
                MXLog.error("[MXAudioOutputRouter] configureOutputPort: routing output to external failed: \(error)")
            }
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
    
    var isExternalDeviceConnected: Bool {
        let route = currentRoute
        for port in route.outputs {
            if port.isExternal {
                return true
            }
        }
        return false
    }
    
    var externalDeviceName: String? {
        let route = currentRoute
        for port in route.outputs {
            if port.isExternal {
                return port.portName
            }
        }
        return nil
    }
    
    var builtInSpeaker: AVAudioSessionDataSourceDescription? {
        guard let sources = outputDataSources else {
            return nil
        }
        for source in sources {
            if source.location == .upper {
                return source
            }
        }
        return nil
    }
    
}

//  MARK: - AVAudioSessionPortDescription Extension

fileprivate extension AVAudioSessionPortDescription {
    
    var isExternal: Bool {
        var result = false
        switch portType {
        case .headphones, .headsetMic, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .carAudio:
            result = true
        default:
            result = false
        }
        
        MXLog.debug("[AVAudioSessionPortDescription] isExternal: returning \(result) for port type: \(portType)")
        
        return result
    }
    
}

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

/// Audio output route class
@objcMembers
public class MXiOSAudioOutputRoute: NSObject {
    
    /// Underlying port for the route. May be nil for `loudSpeakers` typed routes.
    var port: AVAudioSessionPortDescription?
    
    /// Unique identifier for the route
    public var identifier: String
    
    /// Route type of the route
    public var routeType: MXiOSAudioOutputRouteType
    
    /// Name of the route. May not be localized for some route types, especially for `loudSpeakers`
    public var name: String
    
    init(withPort port: AVAudioSessionPortDescription? = nil,
         identifier: String,
         routeType: MXiOSAudioOutputRouteType,
         name: String) {
        self.port = port
        self.identifier = identifier
        self.routeType = routeType
        self.name = name
        super.init()
    }
    
    convenience init(withPort port: AVAudioSessionPortDescription) {
        self.init(withPort: port, identifier: port.uid, routeType: port.routeType, name: port.portName)
    }
    
    public static func == (lhs: MXiOSAudioOutputRoute, rhs: MXiOSAudioOutputRoute) -> Bool {
        return lhs.identifier == rhs.identifier
    }
    
    /// Flag to indicate whether this is an external route
    public var isExternal: Bool {
        switch routeType {
        case .externalWired, .externalBluetooth, .externalCar:
            return true
        default:
            return false
        }
    }
    
    public override var description: String {
        return "<MXiOSAudioOutputRoute: identifier: \(identifier), type: \(routeType), name: \(name) >"
    }
    
}

//  MARK: - AVAudioSessionPortDescription Extension

fileprivate extension AVAudioSessionPortDescription {
    
    var routeType: MXiOSAudioOutputRouteType {
        var result: MXiOSAudioOutputRouteType
        switch portType {
        case .builtInReceiver, .builtInMic:
            result = .builtIn
        case .builtInSpeaker:
            result = .loudSpeakers
        case .headphones, .headsetMic:
            result = .externalWired
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            result = .externalBluetooth
        case .carAudio:
            result = .externalCar
        default:
            result = .builtIn
        }
        
        MXLog.debug("[AVAudioSessionPortDescription] routeType: returning \(result.rawValue) for port type: \(portType)")
        
        return result
    }
    
}

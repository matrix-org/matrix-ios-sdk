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

/// Audio output route type
@objc
public enum MXiOSAudioOutputRouteType: Int {
    /// the speakers at the top of the screen.
    case builtIn
    /// the speakers at the bottom of the phone
    case loudSpeakers
    /// external wired headphones
    case externalWired
    /// external Bluetooth device
    case externalBluetooth
    /// external CarPlay device
    case externalCar
}

extension MXiOSAudioOutputRouteType: CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .builtIn:
            return "builtIn"
        case .loudSpeakers:
            return "loudSpeakers"
        case .externalWired:
            return "externalWired"
        case .externalBluetooth:
            return "externalBluetooth"
        case .externalCar:
            return "externalCar"
        }
    }
    
}

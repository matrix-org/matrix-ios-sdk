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

public extension MXTools {
    
    @objc static let kMXUrlMaxLength = 2028

    /// Readable session state
    /// - Parameter state: session state
    /// - Returns: textual representation for the session state in a human readable way
    @objc
    static func readableSessionState(_ state: MXSessionState) -> String {
        return state.description
    }
    
    @objc
    static func urlString(base: String, queryParameters: [String]) -> String {
        var urlString = base
        var hasQueryParameters = urlString.contains("?")
        for parameter in queryParameters {
            let parameterFormat = !hasQueryParameters ? "?\(parameter)" : "&\(parameter)"
            
            guard urlString.count + parameterFormat.count <= kMXUrlMaxLength else {
                break
            }
            
            hasQueryParameters = true
            urlString.append(parameterFormat)
        }
        return urlString
    }

    @objc
    /// Checks whether a given to-device event is supported or not.
    /// - Parameter event: Event to be checked
    /// - Returns: `true` if the event is supported, otherwise `false`
    static func isSupportedToDeviceEvent(_ event: MXEvent) -> Bool {
        if event.isEncrypted {
            // only support OLM encrypted events
            let algorithm = event.wireContent["algorithm"] as? String
            guard algorithm == kMXCryptoOlmAlgorithm else {
                MXLog.debug("[MXTools] isSupportedToDeviceEvent: not supported event encrypted with other than OLM algorithm: \(String(describing: algorithm))")
                return false
            }
        } else {
            // define unsupported plain event types
            let unsupportedPlainEvents = Set([
                MXEventType.roomKey.identifier,
                MXEventType.roomForwardedKey.identifier,
                MXEventType.secretSend.identifier
            ])
            // make sure that the event type is supported
            if unsupportedPlainEvents.contains(event.type) {
                MXLog.debug("[MXTools] isSupportedToDeviceEvent: not supported plain event with type: \(String(describing: event.type))")
                return false
            }
        }

        return true
    }
}

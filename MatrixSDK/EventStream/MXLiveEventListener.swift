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

/// Protocol used to monitor events of a specific session
@objc
public protocol MXLiveEventListener: AnyObject {
    
    /// Monitor changes to session state
    func onSessionStateChanged(state: MXSessionState)
    
    /// Monitor decryption attempts
    func onLiveEventDecryptionAttempted(event: MXEvent, result:MXEventDecryptionResult)
    
    /// Monitor to device events
    func onLiveToDeviceEvent(event: MXEvent)

}

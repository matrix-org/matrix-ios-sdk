// 
// Copyright 2023 The Matrix.org Foundation C.I.C
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

/// Feature representing the availability of the external rust-based Crypto SDK
/// whilst it is not fully available to everyone and / or is an optional feature.
@objc public protocol MXCryptoV2Feature {
    
    /// Is Crypto SDK currently enabled
    ///
    /// By default this value is `false`. Once enabled, it can only be disabled by logging out,
    /// as there is no way to migrate from from Crypto SDK back to legacy crypto.
    var isEnabled: Bool { get }
    
    /// Manually enable the feature
    ///
    /// This is typically triggered by some user settings / Labs as an experimental feature. Once called
    /// it should restart the session to re-initialize the crypto module.
    func enable()
    
    /// Try to enable the feature for a given user
    ///
    /// This method should only be called when initializing a crypto module (e.g. during app launch or login),
    /// as it is not possible to swap out crypto modules whilst a session is active.
    ///
    /// The availability conditions are implementation details, typically consisting of
    /// various feature flags.
    ///
    /// If available, this method will set `isEnabled` permanently to `true`.
    func enableIfAvailable(forUserId userId: String!)
}

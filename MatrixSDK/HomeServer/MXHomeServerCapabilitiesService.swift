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

/// Describe the type of support for a given feature
@objc public enum MXRoomCapabilitySupportType: Int {
    /// the feature is supported by a stable version
    case supported
    /// the feature is supported by an unstable version (should only be used for dev/experimental purpose).
    case supportedUnstable
    /// the feature is not supported
    case unsupported
    /// the server does not implement room caps
    case unknown
}

///  Used to know current homeserver capabilities as per [matrix.org specifications](https://matrix.org/docs/spec/client_server/r0.6.1#get-matrix-client-r0-capabilities)
///  and [MSC3244](https://github.com/matrix-org/matrix-doc/pull/3244)
@objcMembers
public class MXHomeserverCapabilitiesService: NSObject {
    
    // MARK: - Members
    
    private let session: MXSession
    private let mapper = MXRoomCapabilityTypeMapper()
    private var capabilities: MXHomeserverCapabilities?
    private var currentRequest: MXHTTPOperation?
    
    // MARK: - Properties
    
    /// True if service succesfully read capabilities from the homeserver. False otherwise.
    public var isInitialised: Bool {
        return capabilities != nil
    }
    
    // MARK: - Setup
    
    public init(session: MXSession) {
        self.session = session
    }
    
    // MARK: - Public
    
    /// Force the instance to request its capabilities to the server
    /// - Parameters:
    ///   - completion: A closure called when the operation completes.
    public func update(completion: (() -> Void)? = nil) {
        guard currentRequest == nil else {
            MXLog.debug("[MXHomeServerCapabilitiesService] update: aborted")
            return
        }
        
        self.currentRequest = session.matrixRestClient.homeServerCapabilities { [weak self] response in
            guard let self = self else { return }
            
            switch response {
            case .success(let capabilities):
                self.capabilities = capabilities
            case .failure(let error):
                MXLog.error("[MXHomeServerCapabilitiesService] update: failed", context: error)
            }
            
            self.currentRequest = nil
            
            completion?()
        }
    }
    
    /// True if it is possible to change the password of the account.
    public var canChangePassword: Bool {
        guard let capabilities = self.capabilities else {
            // As per specifications, user can change password by default
            return true
        }
        
        return capabilities.canChangePassword
    }
    
    /// Check if a feature is supported by the homeserver.
    /// - Parameters:
    ///   - feature: Type of the room capability
    /// - Returns:
    ///   - `unknown` if the server does not implement room caps
    ///   - `unsupported` if this feature is not supported
    ///   - `supported` if this feature is supported by a stable version
    ///   - `supportedUnstable` if this feature is supported by an unstable version (should only be used for dev/experimental purpose).
    public func isFeatureSupported(_ feature: MXRoomCapabilityType) -> MXRoomCapabilitySupportType {
        guard let capabilities = self.capabilities else {
            return .unknown
        }
        
        guard let capabilityType = mapper.roomCapabilityStringType(from: feature) else {
            return .unknown
        }
        
        guard let capability = capabilities.roomVersions?.roomCapabilities?[capabilityType.rawValue] else {
            return .unsupported
        }
        
        let preferred = capability.preferred ?? capability.support.last
        guard let versionCapability = capabilities.roomVersions?.supportedVersions.first(where: { $0.version == preferred }) else {
            return .unknown
        }
        
        if versionCapability.statusString == MXRoomVersionStatus.stable.rawValue {
            return .supported
        }
        
        return .supportedUnstable
    }
    
    /// Check if a feature is supported by the homeserver and for a given room version
    /// - Parameters:
    ///   - feature: Type of the room capability
    ///   - roomVersion: Given version of the room
    /// - Returns: `true` if the feature is supported, `false` otherwise
    public func isFeatureSupported(_ feature: MXRoomCapabilityType, by roomVersion: String) -> Bool {
        guard let capabilities = self.capabilities else {
            return false
        }
        
        guard let capabilityType = mapper.roomCapabilityStringType(from: feature) else {
            return false
        }
        
        guard let capability = capabilities.roomVersions?.roomCapabilities?[capabilityType.rawValue] else {
            return false
        }
        
        return capability.preferred == roomVersion || capability.support.contains(roomVersion)
    }
    
    /// Use this method to know if you should force a version when creating a room that requires this feature.
    /// You can also use #isFeatureSupported prior to this call to check if the feature is supported and report some feedback to user.
    /// - Parameters:
    ///   - feature: Type of the room capability
    /// - Returns: The room version if the given feature is supported by the home server
    public func versionOverrideForFeature(_ feature: MXRoomCapabilityType) -> String? {
        guard let capabilityType = mapper.roomCapabilityStringType(from: feature) else {
            return nil
        }

        let capability = self.capabilities?.roomVersions?.roomCapabilities?[capabilityType.rawValue]
        return capability?.preferred ?? capability?.support?.last
    }
}

/// MARK: - Test helper methods
extension MXHomeserverCapabilitiesService {
    
    /// Update the instance with given server capabilities (only for test purpose)
    /// - Parameters:
    ///   - capabilities: new homeserver capabilities
    public func update(with capabilities: MXHomeserverCapabilities?) {
        self.capabilities = capabilities
    }
    
}

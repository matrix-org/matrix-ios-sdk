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

/// MXLocationService error
public enum MXLocationServiceError: Int, Error {
    case missingUserId
    case roomNotFound
    case beaconInfoNotFound
    case beaconInfoAlreadyStopped
    case beaconInfoDoNotBelongToUser
    case beaconInfoExpired
    case unknown
}

// MARK: - MXLocationService errors
extension MXLocationServiceError: CustomNSError {
    public static let errorDomain = "org.matrix.sdk.locationService"

    public var errorCode: Int {
        return Int(rawValue)
    }

    public var errorUserInfo: [String: Any] {
        return [:]
    }
}

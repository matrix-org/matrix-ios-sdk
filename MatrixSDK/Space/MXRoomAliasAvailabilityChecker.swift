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

public enum MXRoomAliasAvailabilityCheckerResult {
    case available
    case invalid
    case notAvailable
    case serverError
}

public class MXRoomAliasAvailabilityChecker {

    static public let validAliasCharacters = Set("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_")

    static public func validate(aliasLocalPart: String, with session: MXSession, completion: @escaping (MXRoomAliasAvailabilityCheckerResult) -> Void) -> MXHTTPOperation? {
        guard !aliasLocalPart.isEmpty else {
            completion(.invalid)
            return nil
        }
        
        let fullAlias = aliasLocalPart.fullLocalAlias(with: session)
        guard aliasLocalPart.filter({ !validAliasCharacters.contains($0) }).count == 0 else {
            completion(.invalid)
            return nil
        }
        
        return session.matrixRestClient.roomId(forRoomAlias: fullAlias) { response in
            if response.isSuccess {
                completion(.notAvailable)
            } else if let error = response.error, let response = MXHTTPOperation.urlResponse(fromError: error), response.statusCode == 404 {
                completion(.available)
            } else {
                completion(.serverError)
            }
        }
    }
}

public extension String {
    func fullLocalAlias(with session: MXSession) -> String {
        guard let homeserverSuffix = session.matrixRestClient.homeserverSuffix else {
            return self
        }
        
        return "#\(self)\(homeserverSuffix)"
    }
    
    func toValidAliasLocalPart() -> String {
        return lowercased().replacingOccurrences(of: " ", with: "-").filter { MXRoomAliasAvailabilityChecker.validAliasCharacters.contains($0) }
    }
}

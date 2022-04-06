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

/// MXRoomAliasAvailabilityChecker validation result
public enum MXRoomAliasAvailabilityCheckerResult {
    /// the alias is valid and is not already used
    case available
    /// the alias contains forbidden characters
    case invalid
    /// the alias is valid but already used
    case notAvailable
    /// the alias is valid but validation request failed
    case serverError
}

/// Helper class used to check the validity and the availability of a user defined alias for a room
public class MXRoomAliasAvailabilityChecker {

    /// set of valid characters of the alias local part
    static public let validAliasCharacters = Set("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_")

    /// checks the validity and the availability of an alias
    /// - Parameters:
    ///   - aliasLocalPart: local part of the alias
    ///   (e.g. for the alias "#my_alias:example.org", the local part is "my_alias")
    ///   - session: instance of the `MXSession` that will be used to perform the request
    ///   - completion: A closure called when the operation completes.
    /// - Returns: a `MXHTTPOperation` instance if the alias is valid and a request is performed to test the availability of the alias. `nil` otherwise
    @discardableResult
    static public func validate(aliasLocalPart: String, with session: MXSession, completion: @escaping (MXRoomAliasAvailabilityCheckerResult) -> Void) -> MXHTTPOperation? {
        guard !aliasLocalPart.isEmpty else {
            completion(.invalid)
            return nil
        }
        
        let fullAlias = MXTools.fullLocalAlias(from: aliasLocalPart, with: session)
        guard aliasLocalPart.filter({ !validAliasCharacters.contains($0) }).count == 0 else {
            completion(.invalid)
            return nil
        }
        
        return session.matrixRestClient.resolveRoomAlias(fullAlias) { response in
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

public extension MXTools {
    /// Generates a full local alias String (e.g. "#my_alias:example.org" for the string "my_alias")
    /// - Parameters:
    ///   - string: based string
    ///   - session: session used to retrieve the homeserver suffix
    /// - Returns:the full local alias String without checking the validity of the alias local part
    static func fullLocalAlias(from string: String, with session: MXSession) -> String {
        guard let homeserverSuffix = session.matrixRestClient.homeserverSuffix else {
            return string
        }
        
        return "#\(string)\(homeserverSuffix)"
    }
    
    /// Generates a valid local alias part String by replacing unauthorised characters
    /// - Parameters:
    ///   - string: based string
    /// - Returns:a valid local alias part.
    static func validAliasLocalPart(from string: String) -> String {
        return string.lowercased().replacingOccurrences(of: " ", with: "-").filter { MXRoomAliasAvailabilityChecker.validAliasCharacters.contains($0) }
    }
    
    /// Extract the valid local alias part String of the string ((e.g. "my_alias" for the string "#my_alias:example.org")
    /// - Parameters:
    ///   - string: based string
    /// - Returns:the valid local alias part extracted from the string.
    static func extractLocalAliasPart(from string: String) -> String {
        var aliasPart = string
        while aliasPart.starts(with: "#") {
            aliasPart.removeFirst()
        }
        if let index = aliasPart.firstIndex(of: ":") {
            aliasPart.removeSubrange(index ..< aliasPart.endIndex)
        }
        return aliasPart
    }
}

/*
 Copyright 2017 Avery Pierce
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import Foundation

/**
 Captures the result of an API call and it's associated success data.
 
 # Examples:
 
 Use a switch statement to handle both a success and an error:
 
     mxRestClient.publicRooms { response in
        switch response {
        case .success(let rooms):
            // Do something useful with these rooms
            break
     
        case .failure(let error):
            // Handle the error in some way
            break
        }
     }
 
 Silently ignore the failure case:
 
     mxRestClient.publicRooms { response in
         guard let rooms = response.value else { return }
         // Do something useful with these rooms
     }

 */
enum MXResponse<T> {
    case success(T)
    case failure(Error)
    
    /// Indicates whether the API call was successful
    var isSuccess: Bool {
        switch self {
        case .success:   return true
        default:        return false
        }
    }
    
    /// The response's success value, if applicable
    var value: T? {
        switch self {
        case .success(let value): return value
        default: return nil
        }
    }
    
    /// Indicates whether the API call failed
    var isFailure: Bool {
        return !isSuccess
    }
    
    /// The response's error value, if applicable
    var error: Error? {
        switch self {
        case .failure(let error): return error
        default: return nil
        }
    }
}

fileprivate extension MXResponse {
    
    /**
     Take the value from an optional, if it's available.
     Otherwise, return a failure with _MXUnknownError
     
     - parameter value: to be captured in a `.success` case, if it's not `nil` and the type is correct.
     
     - returns: `.success(value)` if the value is not `nil`, otherwise `.failure(_MXUnkownError())`
     */
    static func fromOptional(value: Any?) -> MXResponse<T> {
        if let value = value as? T {
            return .success(value)
        } else {
            return .failure(_MXUnknownError())
        }
    }
    
    /**
     Take the error from an optional, if it's available.
     Otherwise, return a failure with _MXUnknownError
     
     - parameter error: to be captured in a `.failure` case, if it's not `nil`.
     
     - returns: `.failure(error)` if the value is not `nil`, otherwise `.failure(_MXUnkownError())`
     */
    static func fromOptional(error: Error?) -> MXResponse<T> {
        return .failure(error ?? _MXUnknownError())
    }
}



/**
 Represents an error that was unexpectedly nil.
 
 This struct only exists to fill in the gaps formed by optionals that
 were created by ObjC headers that don't specify nullibility. Under
 normal controlled circumstances, this should probably never be used.
 */
struct _MXUnknownError : Error {
    var localizedDescription: String {
        return "error object was unexpectedly nil"
    }
}


/// Represents a login flow
enum MXLoginFlowType : String {
    case password = "m.login.password"
    case recaptcha = "m.login.recaptcha"
    case OAuth2 = "m.login.oauth2"
    case emailIdentity = "m.login.email.identity"
    case token = "m.login.token"
    case dummy = "m.login.dummy"
    case emailCode = "m.login.email.code"
}








/// Return a closure that accepts any object, converts it to a MXResponse value, and then executes the provded completion block
fileprivate func success<T>(_ completion: @escaping (MXResponse<T>) -> Void) -> (Any?) -> Void {
    return { completion(.fromOptional(value: $0)) }
}

/// Return a closure that accepts any error, converts it to a MXResponse value, and then executes the provded completion block
fileprivate func error<T>(_ completion: @escaping (MXResponse<T>) -> Void) -> (Error?) -> Void {
    return { completion(.fromOptional(error: $0)) }
}


extension MXRestClient {
    
    
    // MARK: - Initialization
    
    /**
     Create an instance based on homeserver url.
     
     - parameter homeServer: The homeserver address.
     - parameter handler: the block called to handle unrecognized certificate (`nil` if unrecognized certificates are ignored).
     
     - returns: a `MXRestClient` instance.
     */
    @nonobjc convenience init(homeServer: URL, unrecognizedCertificateHandler handler: MXHTTPClientOnUnrecognizedCertificate?) {
        self.init(__homeServer: homeServer.absoluteString, andOnUnrecognizedCertificateBlock: handler)
    }
    
    /**
     Create an instance based on existing user credentials.
     
     - parameter credentials: A set of existing user credentials.
     - parameter handler: the block called to handle unrecognized certificate (`nil` if unrecognized certificates are ignored).
     
     - returns: a `MXRestClient` instance.
     */
    @nonobjc convenience init(credentials: MXCredentials, unrecognizedCertificateHandler handler: MXHTTPClientOnUnrecognizedCertificate?) {
        self.init(__credentials: credentials, andOnUnrecognizedCertificateBlock: handler)
    }

    
    
    
    // MARK: - Registration Operations
    
    /**
     Check whether a username is already in use.
     
     - parameter username: The user name to test.
     - parameter completion: A block object called when the operation is completed.
     - parameter inUse: Whether the username is in use
     
     - returns: a `MXHTTPOperation` instance.
     */
    @nonobjc @discardableResult func isUserNameInUse(_ username: String, completion: @escaping (_ inUse: Bool) -> Void) -> MXHTTPOperation? {
        return __isUserName(inUse: username, callback: completion)
    }
    
    /**
     Get the list of register flows supported by the home server.
     
     - parameter completion: A block object called when the operation is completed.
     - parameter response: Provides the server response as an `MXAuthenticationSession` instance.
     
     - returns: a `MXHTTPOperation` instance.
     */
    @nonobjc @discardableResult func getRegisterSession(completion: @escaping (_ response: MXResponse<MXAuthenticationSession>) -> Void) -> MXHTTPOperation? {
        return __getRegisterSession(success(completion), failure: error(completion))
    }

    
    
    
    
    
    
    
    
    
    /**
     Get the list of public rooms hosted by the home server.
     
     - parameter completion: A block object called when the operation is complete.
     - parameter response: Provides an array of the public rooms on this server on `success`
     
     - returns: a `MXHTTPOperation` instance.
     */
    @nonobjc @discardableResult func publicRooms(completion: @escaping (_ response: MXResponse<[MXPublicRoom]>) -> Void) -> MXHTTPOperation? {
        return __publicRooms(success(completion), failure: error(completion))
    }
    
    
    /**
     Log a user in.
     
     This method manages the full flow for simple login types and returns the credentials of the logged matrix user.
     
     - parameter type: the login type. Only `MXLoginFlowType.password` (m.login.password) is supported.
     - parameter username: the user id (ex: "@bob:matrix.org") or the user id localpart (ex: "bob") of the user to authenticate.
     - parameter password: the user's password.
     - parameter completion: A block object called when the operation succeeds.
     
     - parameter response: Provides credentials for this user on `success`
     
     - returns: a `MXHTTPOperation` instance.
     */
    @nonobjc @discardableResult func login(type loginType: MXLoginFlowType = .password, username: String, password: String, completion: @escaping (_ response: MXResponse<MXCredentials>) -> Void) -> MXHTTPOperation? {
        return __login(withLoginType: loginType.rawValue, username: username, password: password, success: success(completion), failure: error(completion))
    }
}

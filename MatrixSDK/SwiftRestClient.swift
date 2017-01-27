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



extension MXRestClient {
    
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

    
    
    
    /**
     Check whether a username is already in use.
     
     - parameter username: The user name to test.
     - parameter completion: A block object called when the operation is completed.
     - parameter inUse: Whether the username is in use
     
     - returns: a `MXHTTPOperation` instance.
     */
    @nonobjc @discardableResult func isUserNameInUse(_ username: String, completion: @escaping (_ inUse: Bool) -> Void) -> MXHTTPOperation? {
        let operation = __isUserName(inUse: username, callback: completion)
        return operation
    }
    
    
    /**
     Get the list of public rooms hosted by the home server.
     
     - parameter completion: A block object called when the operation is complete.
     - parameter response: Provides an array of the public rooms on this server on `success`
     
     - returns: a `MXHTTPOperation` instance.
     */
    @nonobjc @discardableResult func publicRooms(completion: @escaping (_ response: MXResponse<[MXPublicRoom]>) -> ()) -> MXHTTPOperation? {
        let operation = __publicRooms({ (roomObjects) in
            let publicRooms = roomObjects?.flatMap({ return $0 as? MXPublicRoom }) ?? []
            completion(.success(publicRooms))
        }) { (error) in
            completion(.failure(error ?? _MXUnknownError()))
        }
        
        return operation
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
    @nonobjc @discardableResult func login(type loginType: MXLoginFlowType = .password, username: String, password: String, completion: @escaping (_ response: MXResponse<MXCredentials>) -> ()) -> MXHTTPOperation? {
        let operation = __login(withLoginType: loginType.rawValue, username: username, password: password, success: { (credentials) in
            if let credentials = credentials {
                completion(.success(credentials))
            } else {
                completion(.failure(_MXUnknownError()))
            }
        }) { (error) in
            completion(.failure(error ?? _MXUnknownError()))
        }
        
        return operation
    }
}

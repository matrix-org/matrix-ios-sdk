//
//  SwiftRestClient.swift
//  MatrixSDK
//
//  Created by Avery Pierce on 1/26/17.
//  Copyright © 2017 matrix.org. All rights reserved.
//

import Foundation

enum RestResponse<T> {
    case success(T)
    case failure(Error)
}

struct UnknownError : Error {
    var localizedDescription: String {
        return "An unknown error has occurred"
    }
}


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
    
    @nonobjc convenience init(homeServer: String, onUnrecognizedCertificate block: MXHTTPClientOnUnrecognizedCertificate?) {
        self.init(__homeServer: homeServer, andOnUnrecognizedCertificateBlock: block)
    }
    
    @nonobjc convenience init(credentials: MXCredentials, onUnrecognizedCertificate block: MXHTTPClientOnUnrecognizedCertificate?) {
        self.init(__credentials: credentials, andOnUnrecognizedCertificateBlock: block)
    }

    
    @nonobjc @discardableResult func publicRooms(completion: @escaping (RestResponse<[MXPublicRoom]>) -> ()) -> MXHTTPOperation? {
        let operation = __publicRooms({ (roomObjects) in
            let publicRooms = roomObjects?.flatMap({ return $0 as? MXPublicRoom }) ?? []
            completion(.success(publicRooms))
        }) { (someError) in
            let error = someError ?? UnknownError()
            completion(.failure(error))
        }
        
        return operation
    }
    
    @nonobjc @discardableResult func login(type loginType: MXLoginFlowType = .password, username: String, password: String, completion: @escaping (RestResponse<MXCredentials>) -> ()) -> MXHTTPOperation? {
        let operation = __login(withLoginType: loginType.rawValue, username: username, password: password, success: { (credentials) in
            if let credentials = credentials {
                completion(.success(credentials))
            } else {
                completion(.failure(UnknownError()))
            }
        }) { (error) in
            completion(.failure(error ?? UnknownError()))
        }
        
        return operation
    }
}


struct SwiftTryMe {
    func test() {
        
        let client = MXRestClient(homeServer: "https://matrix.org", onUnrecognizedCertificate: nil)
        client.publicRooms { (result) in
            switch result {
            case .success(let rooms):
                print(rooms)
            case .failure(let error):
                print(error)
            }
        }
        
        client.login(username: "username", password: "password") { response in
            switch response {
            case .success(let certificate):
                // Do something with certificate
                print("Success!")
                
            case .failure(let error):
                // Do something with the error
                print("Failure!")
            }
        }
    }
}

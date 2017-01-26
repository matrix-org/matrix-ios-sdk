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

class SwiftRestClient {
    private let mxRestClient: MXRestClient
    
    /**
     Create an instance based on homeserver url.
     
     @param homeserver the homeserver URL.
     @param onUnrecognizedCertBlock the block called to handle unrecognized certificate (nil if unrecognized certificates are ignored).
     @return a MXRestClient instance.
     */
    init(homeServer: String, onUnrecognizedCertificate block: MXHTTPClientOnUnrecognizedCertificate?) {
        mxRestClient = MXRestClient(homeServer: homeServer, andOnUnrecognizedCertificateBlock: block)
    }
    
    /**
     Create an instance based on a matrix user account.
     
     @param credentials the response to a login or a register request.
     @param onUnrecognizedCertBlock the block called to handle unrecognized certificate (nil if unrecognized certificates are ignored).
     @return a MXRestClient instance.
     */
    init(credentials: MXCredentials, onUnrecognizedCertificate block: MXHTTPClientOnUnrecognizedCertificate?) {
        mxRestClient = MXRestClient(credentials: credentials, andOnUnrecognizedCertificateBlock: block)
    }
    
    /**
     Get the list of public rooms hosted by the home server.
     
     @param success A block object called when the operation succeeds. rooms is an array of MXPublicRoom objects
     @param failure A block object called when the operation fails.
     
     @return a MXHTTPOperation instance.
     */
    @discardableResult func publicRooms(completion: @escaping (RestResponse<[MXPublicRoom]>) -> ()) -> MXHTTPOperation? {
        let operation = mxRestClient.publicRooms({ (roomObjects) in
            let publicRooms = roomObjects?.flatMap({ return $0 as? MXPublicRoom }) ?? []
            completion(.success(publicRooms))
        }) { (someError) in
            let error = someError ?? UnknownError()
            completion(.failure(error))
        }
        
        return operation
    }
}


struct SwiftTest {
    func test() {
        
        let client = SwiftRestClient(homeServer: "https://matrix.org", onUnrecognizedCertificate: nil)
        client.publicRooms { (result) in
            switch result {
            case .success(let rooms):
                print(rooms)
            case .failure(let error):
                print(error)
            }
        }
    }
}

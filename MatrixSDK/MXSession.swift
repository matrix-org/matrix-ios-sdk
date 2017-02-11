//
//  MXSession.swift
//  MatrixSDK
//
//  Created by Avery Pierce on 2/11/17.
//  Copyright © 2017 matrix.org. All rights reserved.
//

import Foundation


public extension MXSession {
    
    /**
     Start fetching events from the home server.
     
     If the attached MXStore does not cache data permanently, the function will begin by making
     an initialSync request to the home server to get information about the rooms the user has
     interactions with.
     Then, it will start the events streaming, a long polling connection to the home server to
     listen to new coming events.
     
     If the attached MXStore caches data permanently, the function will do an initialSync only at
     the first launch. Then, for next app launches, the SDK will load events from the MXStore and
     will resume the events streaming from where it had been stopped the time before.
     
     - parameters:
        - limit: The number of messages to retrieve in each room. If `nil`, this preloads 10 messages.
     Use this argument to use a custom limit.
        - completion: A block object called when the operation completes. In case of failure during
     the initial sync, the session state is `MXSessionStateInitialSyncFailed`.
        - response: Indicates whether the operation was successful.
     */
    @nonobjc func start(withMessagesLimit limit: UInt? = nil, completion: @escaping (_ response: MXResponse<Void>) -> Void) {
        if let limit = limit {
            __start(withMessagesLimit: limit, onServerSyncDone: currySuccess(completion), failure: curryFailure(completion))
        } else {
            __start(currySuccess(completion), failure: curryFailure(completion))
        }
    }
    
    
    /**
     Perform an events stream catchup in background (by keeping user offline).
     
     - parameters:
        - timeout: the max time to perform the catchup
        - completion: A block called when the SDK has completed a catchup, or times out.
        - response: Indicates whether the sync was successful.
     */
    @nonobjc func backgroundSync(withTimeout timeout: TimeInterval, completion: @escaping (_ response: MXResponse<Void>) -> Void) {
        let timeoutMilliseconds = UInt32(timeout * 1000)
        __backgroundSync(timeoutMilliseconds, success: currySuccess(completion), failure: curryFailure(completion))
    }
    
    
    
    
    /**
     Invalidate the access token, so that it can no longer be used for authorization.
     
     - parameters:
        - completion: A block called when the SDK has completed a catchup, or times out.
        - response: Indicates whether the sync was successful.
     
     - returns: an `MXHTTPOperation` instance.
     */
    @nonobjc @discardableResult func logout(completion: @escaping (_ response: MXResponse<Void>) -> Void) -> MXHTTPOperation? {
        return __logout(currySuccess(completion), failure: curryFailure(completion))
    }
    
    
    
    /**
     Define the Matrix storage component to use.
     
     It must be set before calling [MXSession start].
     Else, by default, the MXSession instance will use MXNoStore as storage.
     
     - parameters:
        - store: the store to use for the session.
        - completion: A block object called when the operation completes. If the operation was
     successful, the SDK is then able to serve this data to its client. Note the data may not
     be up-to-date. You need to call [MXSession start] to ensure the sync with the home server.
        - response: indicates whether the operation was successful.
     */
    @nonobjc func setStore(_ store: MXStore, completion: @escaping (_ response: MXResponse<Void>) -> Void) {
        __setStore(store, success: currySuccess(completion), failure: curryFailure(completion))
    }
    
    
    /**
     Enable End-to-End encryption.
     
     In case of enabling, the operation will complete when the session will be ready
     to make encrytion with other users devices
     
     - parameters:
        - isEnabled: `false` stops crypto and erases crypto data.
        - completion: A block called when the SDK has completed a catchup, or times out.
        - response: Indicates whether the sync was successful.
     
     - returns: the HTTP operation that may be required. Can be nil.
     */
    @nonobjc @discardableResult func enableCrypto(_ isEnabled: Bool, completion: @escaping (_ response: MXResponse<Void>) -> Void) -> MXHTTPOperation? {
        return __enableCrypto(isEnabled, success: currySuccess(completion), failure: curryFailure(completion))
    }
    
    
    
    
    
    
    
    
}

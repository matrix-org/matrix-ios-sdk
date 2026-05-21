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

@objc
public extension MXRestClient {
    
    /// Download users keys by chunks.
    ///
    /// - Parameters:
    ///   - users: list of users to get keys for.
    ///   - token: sync token to pass in the query request, to help.
    ///   - chunkSize: max number of users to ask for in one CS API request.
    ///   - success: A block object called when the operation succeeds.
    ///   - failure: A block object called when the operation fails.
    /// - Returns: a MXHTTPOperation instance.
    func downloadKeysByChunk(forUsers users: [String],
                             token: String?,
                             chunkSize: Int = 250,
                             success: @escaping (_ keysQueryResponse: MXKeysQueryResponse) -> Void,
                             failure: @escaping (_ error: NSError?) -> Void) -> MXHTTPOperation {
        
        // Do not chunk if not needed
        if users.count <= chunkSize {
            return self.downloadKeys(forUsers: users, token: token) { response in
                switch response {
                    case .success(let keysQueryResponse):
                        success(keysQueryResponse)
                    case .failure(let error):
                        failure(error as NSError)
                }
            }
        }
        
        MXLog.debug("[MXRestClient+Extensions] downloadKeysByChunk: \(users.count) users with chunkSize:\(chunkSize)")
        
        // An arbitrary MXHTTPOperation. It will not cancel requests
        // but it will avoid to call callbacks in case of a cancellation is requested
        let operation = MXHTTPOperation()
        
        let group = DispatchGroup()
        var responses = [MXResponse<MXKeysQueryResponse>]()
        users.chunked(into: chunkSize).forEach { chunkedUsers in
            group.enter()
            self.downloadKeys(forUsers: chunkedUsers, token: token) { response in
                switch response {
                    case .success(let keysQueryResponse):
                        MXLog.debug("[MXRestClient+Extensions] downloadKeysByChunk: Got intermediate response. Got device keys for %@ users. Got cross-signing keys for %@ users \(String(describing: keysQueryResponse.deviceKeys.userIds()?.count)) \(String(describing: keysQueryResponse.crossSigningKeys.count))")
                    case .failure(let error):
                        MXLog.debug("[MXRestClient+Extensions] downloadKeysByChunk: Got intermediate error. Error: \(error)")
                }

                responses.append(response)
                group.leave()
            }
        }
        
        group.notify(queue: self.completionQueue) {
            MXLog.debug("[MXRestClient+Extensions] downloadKeysByChunk: Got all responses")
                
            guard operation.isCancelled == false else {
                MXLog.debug("[MXRestClient+Extensions] downloadKeysByChunk: Request was cancelled")
                return
            }
            
            // Gather all responses in one
            let response = responses.reduce(.success(MXKeysQueryResponse()), +)
            switch response {
                case .success(let keysQueryResponse):
                    success(keysQueryResponse)
                case .failure(let error):
                    failure(error as NSError)
            }
        }
        
        return operation
    }
    
    /// Download users keys by chunks.
    ///
    /// - Parameters:
    ///   - users: list of users to get keys for.
    ///   - token: sync token to pass in the query request, to help.
    ///   - chunkSize: max number of users to ask for in one CS API request.
    ///   - success: A block object called when the operation succeeds.
    ///   - failure: A block object called when the operation fails.
    /// - Returns: a MXHTTPOperation instance.
    func downloadKeysByChunkRaw(forUsers users: [String],
                             token: String?,
                             chunkSize: Int = 250,
                             success: @escaping (_ keysQueryResponse: MXKeysQueryResponseRaw) -> Void,
                             failure: @escaping (_ error: NSError?) -> Void) -> MXHTTPOperation {
        
        // Do not chunk if not needed
        if users.count <= chunkSize {
            return self.downloadKeysRaw(forUsers: users, token: token) { response in
                switch response {
                    case .success(let keysQueryResponse):
                        success(keysQueryResponse)
                    case .failure(let error):
                        failure(error as NSError)
                }
            }
        }
        
        MXLog.debug("[MXRestClient+Extensions] downloadKeysByChunk: \(users.count) users with chunkSize:\(chunkSize)")
        
        // An arbitrary MXHTTPOperation. It will not cancel requests
        // but it will avoid to call callbacks in case of a cancellation is requested
        let operation = MXHTTPOperation()
        
        let group = DispatchGroup()
        var responses = [MXResponse<MXKeysQueryResponseRaw>]()
        users.chunked(into: chunkSize).forEach { chunkedUsers in
            group.enter()
            self.downloadKeysRaw(forUsers: chunkedUsers, token: token) { response in
                switch response {
                    case .success(let keysQueryResponse):
                        MXLog.debug("[MXRestClient+Extensions] downloadKeysByChunk: Got intermediate response. Got device keys for %@ users. Got cross-signing keys for %@ users \(String(describing: keysQueryResponse.deviceKeys.keys.count)) \(String(describing: keysQueryResponse.crossSigningKeys.count))")
                    case .failure(let error):
                        MXLog.debug("[MXRestClient+Extensions] downloadKeysByChunk: Got intermediate error. Error: \(error)")
                }

                responses.append(response)
                group.leave()
            }
        }
        
        group.notify(queue: self.completionQueue) {
            MXLog.debug("[MXRestClient+Extensions] downloadKeysByChunk: Got all responses")
                
            guard operation.isCancelled == false else {
                MXLog.debug("[MXRestClient+Extensions] downloadKeysByChunk: Request was cancelled")
                return
            }
            
            // Gather all responses in one
            let response = responses.reduce(.success(MXKeysQueryResponseRaw()), +)
            switch response {
                case .success(let keysQueryResponse):
                    success(keysQueryResponse)
                case .failure(let error):
                    failure(error as NSError)
            }
        }
        
        return operation
    }
}

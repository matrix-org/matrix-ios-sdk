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
        
        // An arbitrary MXHTTPOperation. It will not cancel requests
        // but it will avoid to call callbacks in case of a cancellation is requested
        let operation = MXHTTPOperation()
        
        let group = DispatchGroup()
        var responses = [MXResponse<MXKeysQueryResponse>]()
        users.chunked(into: chunkSize).forEach { chunkedUsers in
            group.enter()
            self.downloadKeys(forUsers: chunkedUsers, token: token) { response in
                responses.append(response)
                group.leave()
            }
        }
        
        group.notify(queue: self.completionQueue) {
            guard operation.isCancelled == false else {
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
}

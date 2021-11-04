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

/// MXThreadingService error
public enum MXThreadingServiceError: Int, Error {
    case sessionNotFound
    case unknown
}

// MARK: - MXThreadingService errors
extension MXThreadingServiceError: CustomNSError {
    public static let errorDomain = "org.matrix.sdk.threadingservice"

    public var errorCode: Int {
        return Int(rawValue)
    }

    public var errorUserInfo: [String: Any] {
        return [:]
    }
}

@objcMembers
public class MXThreadingService: NSObject {
    
    private weak var session: MXSession?
    
    private var threads: [String: MXThread] = [:]
    
    public init(withSession session: MXSession) {
        self.session = session
        super.init()
    }
    
    public func handleEvent(_ event: MXEvent) {
        guard let threadIdentifier = event.threadIdentifier else {
            //  event is not in a thread
            return
        }
        
        if let thread = thread(withId: threadIdentifier) {
            //  add event to the thread if found
            thread.addEvent(event)
        } else {
            //  create the thread for the first time
            let thread: MXThread
            //  try to find the root event in the session store
            if let rootEvent = session?.store.event(withEventId: threadIdentifier, inRoom: event.roomId) {
                thread = MXThread(withRootEvent: rootEvent)
            } else {
                thread = MXThread(withIdentifier: threadIdentifier, roomId: event.roomId)
            }
            saveThread(thread)
        }
    }
    
    public func isEventThreadRoot(_ event: MXEvent) -> Bool {
        return thread(withId: event.eventId) != nil
    }
    
    public func thread(withId identifier: String) -> MXThread? {
        objc_sync_enter(threads)
        let result = threads[identifier]
        objc_sync_exit(threads)
        return result
    }
    
    private func saveThread(_ thread: MXThread) {
        objc_sync_enter(threads)
        threads[thread.identifier] = thread
        objc_sync_exit(threads)
    }
    
    public func allThreads(inRoom roomId: String,
                           completion: @escaping (MXResponse<[MXThread]>) -> Void) {
        guard let session = session else {
            completion(.failure(MXThreadingServiceError.sessionNotFound))
            return
        }
        
        let filter = MXRoomEventFilter()
        filter.relationTypes = [MXEventRelationTypeThread]
        
        session.matrixRestClient.messages(forRoom: roomId,
                                          from: "",
                                          direction: .backwards,
                                          limit: nil,
                                          filter: filter) { response in
            switch response {
            case .success(let paginationResponse):
                if let rootEvents = paginationResponse.chunk {
                    let threads = rootEvents.map({ MXThread(withRootEvent: $0) })
                    completion(.success(threads))
                } else {
                    completion(.success([]))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
}

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

/// MXSpaceService enables to handle spaces.
@objcMembers
public class MXSpaceService: NSObject {
    
    // MARK: - Properties
    
    private unowned let session: MXSession
    
    private lazy var stateEventBuilder: MXRoomInitialStateEventBuilder = {
        return MXRoomInitialStateEventBuilder()
    }()
    
    // MARK: - Setup
    
    public init(session: MXSession) {
        self.session = session
    }
    
    // MARK: - Public
    
    /// Create a space.
    /// - Parameters:
    ///   - parameters: The parameters for space creation.
    ///   - completion: A closure called when the operation completes.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func createSpace(with parameters: MXSpaceCreationParameters, completion: @escaping (MXResponse<MXSpace>) -> Void) -> MXHTTPOperation {
        return self.session.createRoom(parameters: parameters) { (response) in
            switch response {
            case .success(let room):
                let space: MXSpace = MXSpace(room: room)
                completion(.success(space))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Create a space shortcut.
    /// - Parameters:
    ///   - name: The space name.
    ///   - topic: The space topic.
    ///   - isPublic: true to indicate to use public chat presets and join the space without invite or false to use private chat presets and join the space on invite.
    ///   - completion: A closure called when the operation completes.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func createSpace(withName name: String, topic: String, isPublic: Bool, completion: @escaping (MXResponse<MXSpace>) -> Void) -> MXHTTPOperation {
        let parameters = MXSpaceCreationParameters()
        parameters.name = name
        parameters.topic = topic
        parameters.preset = isPublic ? kMXRoomPresetPublicChat : kMXRoomPresetPrivateChat
        
        if isPublic {
            let guestAccessStateEvent = self.stateEventBuilder.buildGuestAccessEvent(withAccess: .canJoin)
                                    
            let historyVisibilityStateEvent = self.stateEventBuilder.buildHistoryVisibilityEvent(withVisibility: .worldReadable)
            
            parameters.addOrUpdateInitialStateEvent(guestAccessStateEvent)
            parameters.addOrUpdateInitialStateEvent(historyVisibilityStateEvent)
        }
        
        return self.createSpace(with: parameters, completion: completion)
    }
    
    /// Get a space from a roomId.
    /// - Parameter spaceId: The id of the space.
    /// - Returns: A MXSpace with the associated roomId or null if room type is not space.
    public func getSpace(withId spaceId: String) -> MXSpace? {
        let room = self.session.room(withRoomId: spaceId)
        return room?.toSpace()
    }
}

// MARK: - Objective-C interface
extension MXSpaceService {
    
    /// Create a space.
    /// - Parameters:
    ///   - parameters: The parameters for space creation.
    ///   - success: A closure called when the operation is complete.
    ///   - failure: A closure called  when the operation fails.
    /// - Returns: a `MXHTTPOperation` instance.
    public func createSpace(with parameters: MXSpaceCreationParameters, success: @escaping (MXSpace) -> Void, failure: @escaping (Error) -> Void) -> MXHTTPOperation {
        return self.createSpace(with: parameters) { (response) in
            uncurryResponse(response, success: success, failure: failure)
        }
    }
    
    /// Create a space shortcut.
    /// - Parameters:
    ///   - name: The space name.
    ///   - topic: The space topic.
    ///   - isPublic: true to indicate to use public chat presets and join the space without invite or false to use private chat presets and join the space on invite.
    ///   - success: A closure called when the operation is complete.
    ///   - failure: A closure called  when the operation fails.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func createSpace(withName name: String, topic: String, isPublic: Bool, success: @escaping (MXSpace) -> Void, failure: @escaping (Error) -> Void) -> MXHTTPOperation {
        return self.createSpace(withName: name, topic: topic, isPublic: isPublic) { (response) in
            uncurryResponse(response, success: success, failure: failure)
        }
    }
}

// MARK: - Internal room additions
extension MXRoom {
    
    func toSpace() -> MXSpace? {
        guard self.summary.roomType == .space else {
            return nil
        }
        return MXSpace(room: self)
    }
}

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

/// MXSpace operation error
public enum MXSpaceError: Int, Error {
    case homeserverNameNotFound
    case unknown
}

extension MXSpaceError: CustomNSError {
    public static let errorDomain = "org.matrix.sdk.space"

    public var errorCode: Int {
        return Int(rawValue)
    }

    public var errorUserInfo: [String: Any] {
        return [:]
    }
}

/// A Matrix space enables to collect rooms together into groups. Such collections of rooms are referred as "spaces" (see https://github.com/matrix-org/matrix-doc/blob/matthew/msc1772/proposals/1772-groups-as-rooms.md).
@objcMembers
public class MXSpace: NSObject {
    
    // MARK: - Properties
    
    /// The underlying room
    public let room: MXRoom
    
    /// Shortcut to the room roomId
    public var spaceId: String {
        return self.room.roomId
    }
    
    /// Shortcut to the room summary
    public var summary: MXRoomSummary? {
        return self.room.summary
    }
    
    public private(set) var childSpaces: [MXSpace] = []
    public private(set) var childRoomIds: [String] = []
    public private(set) var otherMembersId: [String] = []
    public private(set) var membersId: [String] = []
    
    public var lastSpaceChildrenSummary: MXSpaceChildrenSummary?

    // MARK: - Setup
    
    public init(room: MXRoom) {
        self.room = room
        super.init()
    }
    
    // MARK: - Public
    
    /// Update children and members from room states and members
    /// - Parameters:
    ///   - completion: A closure called when the operation completes.
    public func readChildRoomsAndMembers(completion: @escaping () -> Void) {
        let myUserId = room.mxSession.myUserId

        room.state { [weak self] roomState in
            roomState?.stateEvents.forEach({ event in
                if event.eventType == .spaceChild {
                    self?.childRoomIds.append(event.stateKey)
                }
            })
            
            self?.room.members { [weak self] response in
                guard let members = response.value as? MXRoomMembers else {
                    return
                }

                var otherMembersId: [String] = []
                var membersId: [String] = []
                members.members.forEach { roomMember in
                    membersId.append(roomMember.userId)
                    if roomMember.userId != myUserId {
                        otherMembersId.append(roomMember.userId)
                    }
                }
                self?.otherMembersId = otherMembersId
                self?.membersId = membersId
                
                completion()
            }
        }
    }
        
    /// Add child space or child room to the current space.
    /// - Parameters:
    ///   - roomId: The room id of the child space or child room.
    ///   - viaServers: List of candidate servers that can be used to join the space. Children where via is not present are ignored.
    ///   If nil value is set current homeserver will be used as via server.
    ///   - order: Is a string which is used to provide a default ordering of siblings in the room list. Orders should be a string of ascii characters in the range \x20 (space) to \x7F (~), and should be less or equal 50 characters.
    ///   - autoJoin: Allows a space admin to list the sub-spaces and rooms in that space which should be automatically joined by members of that space.
    ///   - suggested: Indicates that the child should be advertised to members of the space by the client. This could be done by showing them eagerly in the room list.
    ///   - completion: A closure called when the operation completes. Provides the event id of the event generated on the home server on success.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func addChild(roomId: String,
                         viaServers: [String]? = nil,
                         order: String? = nil,
                         autoJoin: Bool = false,
                         suggested: Bool = false,
                         completion: @escaping (_ response: MXResponse<String?>) -> Void) -> MXHTTPOperation? {
        
        let finalViaServers: [String]
        
        if let viaServers = viaServers {
            finalViaServers = viaServers
        } else {
            // If viaServers is nil use the current homeserver as via server
            guard let homeserverName = self.room.mxSession.credentials.homeServerName() else {
                completion(.failure(MXSpaceError.homeserverNameNotFound))
                return nil
            }
            finalViaServers = [homeserverName]
        }
                                            
        let spaceChild = MXSpaceChildContent()
        spaceChild.via = finalViaServers
        spaceChild.order = order
        spaceChild.autoJoin = autoJoin
        spaceChild.suggested = suggested
        
        guard let stateEventContent = spaceChild.jsonDictionary() as? [String: Any] else {
            fatalError("[MXSpace] MXSpaceChildContent dictionary cannot be nil")
        }
        
        return self.room.sendStateEvent(.spaceChild,
                                 content: stateEventContent,
                                 stateKey: roomId,
                                 completion: completion)
    }
    
    /// Update child spaces using the list of spaces
    /// - Parameters:
    ///   - spacesPerId: complete list of spaces by space ID
    public func updateChildSpaces(with spacesPerId: [String: MXSpace]) {
        self.childRoomIds.forEach { roomId in
            if let space = spacesPerId[roomId] {
                self.childSpaces.append(space)
            }
        }
    }
    
    /// Update child rooms using the list of direct rooms
    /// - Parameters:
    ///   - directRoomsPerMember: complete list of direct rooms by room ID
    public func updateChildDirectRooms(with directRoomsPerMember: [String : [MXRoom]]) {
        self.updateChildRooms(from: self, with: directRoomsPerMember)
        self.childSpaces.forEach { space in
            self.updateChildRooms(from: space, with: directRoomsPerMember)
        }
    }
    
    /// Check if the room identified with an ID is a child of the space
    /// - Parameters:
    ///   - roomId: The room id of the potential child room.
    /// - Returns: `true` if the room identified is a child, `false` atherwise
    public func isRoomAChild(roomId: String) -> Bool {
        return childRoomIds.contains(roomId)
    }
    
    // MARK: - Private
    
    private func updateChildRooms(from space: MXSpace, with directRoomsPerMember: [String : [MXRoom]]) {
        space.otherMembersId.forEach { memberId in
            let rooms = directRoomsPerMember[memberId] ?? []
            self.childRoomIds.append(contentsOf: rooms.compactMap({ room in
                return room.roomId
            }))
        }
    }
}

// MARK: - Objective-C
extension MXSpace {
    
    /// Add child space or child room to the current space.
    /// - Parameters:
    ///   - roomId: The room id of the child space or child room.
    ///   - viaServers: List of candidate servers that can be used to join the space. Children where via is not present are ignored.
    ///   If nil value is set current homeserver will be used as via server.
    ///   - order: Is a string which is used to provide a default ordering of siblings in the room list. Orders should be a string of ascii characters in the range \x20 (space) to \x7F (~), and should be less or equal 50 characters.
    ///   - autoJoin: Allows a space admin to list the sub-spaces and rooms in that space which should be automatically joined by members of that space.
    ///   - suggested: Indicates that the child should be advertised to members of the space by the client. This could be done by showing them eagerly in the room list.
    ///   - success: A closure called when the operation is complete. Provides the event id of the event generated on the home server on success.
    ///   - failure: A closure called  when the operation fails.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    @objc public func addChild(roomId: String,
                         viaServers: [String]?,
                         order: String?,
                         autoJoin: Bool,
                         suggested: Bool,
                         success: @escaping (String?) -> Void,
                         failure: @escaping (Error) -> Void) -> MXHTTPOperation? {
        return self.addChild(roomId: roomId, viaServers: viaServers, order: order, autoJoin: autoJoin, suggested: suggested) { (response) in
            uncurryResponse(response, success: success, failure: failure)
        }
    }
}

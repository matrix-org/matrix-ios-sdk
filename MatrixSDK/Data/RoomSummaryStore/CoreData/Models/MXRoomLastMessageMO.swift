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
import CoreData

@objc(MXRoomLastMessageMO)
public class MXRoomLastMessageMO: NSManagedObject {

    internal static func typedFetchRequest() -> NSFetchRequest<MXRoomLastMessageMO> {
        return NSFetchRequest<MXRoomLastMessageMO>(entityName: entityName)
    }

    @NSManaged public var s_eventId: String
    @NSManaged public var s_originServerTs: UInt64
    @NSManaged public var s_isEncrypted: Bool
    @NSManaged public var s_hasDecryptionError: Bool
    @NSManaged public var s_sender: String
    @NSManaged public var s_sensitiveData: Data?
    
    @discardableResult
    internal static func insert(roomLastMessage lastMessage: MXRoomLastMessage,
                                into moc: NSManagedObjectContext) -> MXRoomLastMessageMO {
        let model = MXRoomLastMessageMO(context: moc)
        
        model.update(withLastMessage: lastMessage)
        
        return model
    }
    
    internal func update(withLastMessage lastMessage: MXRoomLastMessage) {
        s_eventId = lastMessage.eventId
        s_originServerTs = lastMessage.originServerTs
        s_isEncrypted = lastMessage.isEncrypted
        s_hasDecryptionError = lastMessage.hasDecryptionError
        s_sender = lastMessage.sender
        s_sensitiveData = lastMessage.sensitiveData()
    }
}

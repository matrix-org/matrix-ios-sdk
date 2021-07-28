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

@objc(MXRoomLastMessageModel)
public class MXRoomLastMessageModel: NSManagedObject {
    
    private enum Constants {
        static let entityName: String = "MXRoomLastMessageModel"
    }

    internal static func typedFetchRequest() -> NSFetchRequest<MXRoomLastMessageModel> {
        return NSFetchRequest<MXRoomLastMessageModel>(entityName: Constants.entityName)
    }

    @NSManaged public var eventId: String
    @NSManaged public var originServerTs: UInt64
    @NSManaged public var isEncrypted: Bool
    @NSManaged public var sender: String
    @NSManaged public var text: String?
    @NSManaged public var attributedText: Data?
    @NSManaged public var others: Data?
    
    internal static func from(roomLastMessage lastMessage: MXRoomLastMessage,
                              in managedObjectContext: NSManagedObjectContext) -> MXRoomLastMessageModel {
        guard let model = NSEntityDescription.insertNewObject(forEntityName: Constants.entityName,
                                                              into: managedObjectContext) as? MXRoomLastMessageModel else {
            fatalError("[MXRoomLastMessageModel] from: could not initialize new model")
        }
        
        model.eventId = lastMessage.eventId
        model.originServerTs = lastMessage.originServerTs
        model.isEncrypted = lastMessage.isEncrypted
        model.sender = lastMessage.sender
        model.text = lastMessage.text
        
        if let attributedText = lastMessage.attributedText {
            model.attributedText = NSKeyedArchiver.archivedData(withRootObject: attributedText)
        } else {
            model.attributedText = nil
        }
        
        if let others = lastMessage.others {
            model.others = NSKeyedArchiver.archivedData(withRootObject: others)
        } else {
            model.others = nil
        }
        
        return model
    }
    
}

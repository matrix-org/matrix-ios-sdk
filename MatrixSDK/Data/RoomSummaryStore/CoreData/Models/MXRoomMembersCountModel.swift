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

@objc(MXRoomMembersCountModel)
public class MXRoomMembersCountModel: NSManagedObject {
    
    private enum Constants {
        static let entityName: String = "MXRoomMembersCountModel"
    }

    internal static func typedFetchRequest() -> NSFetchRequest<MXRoomMembersCountModel> {
        return NSFetchRequest<MXRoomMembersCountModel>(entityName: Constants.entityName)
    }

    @NSManaged public var s_members: Int16
    @NSManaged public var s_joined: Int16
    @NSManaged public var s_invited: Int16
    
    @discardableResult
    internal static func insert(roomMembersCount membersCount: MXRoomMembersCount,
                                into moc: NSManagedObjectContext) -> MXRoomMembersCountModel {
        guard let model = NSEntityDescription.insertNewObject(forEntityName: Constants.entityName,
                                                              into: moc) as? MXRoomMembersCountModel else {
            fatalError("[MXRoomMembersCountModel] insert: could not initialize new model")
        }
        
        model.s_members = Int16(membersCount.members)
        model.s_joined = Int16(membersCount.joined)
        model.s_invited = Int16(membersCount.invited)
        
        return model
    }
    
}

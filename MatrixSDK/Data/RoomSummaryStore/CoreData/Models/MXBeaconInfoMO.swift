// 
// Copyright 2022 The Matrix.org Foundation C.I.C
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

@objc(MXBeaconInfoMO)
public class MXBeaconInfoMO: NSManagedObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MXBeaconInfoMO> {
        return NSFetchRequest<MXBeaconInfoMO>(entityName: "MXBeaconInfo")
    }

    @NSManaged public var s_description: String?
    @NSManaged public var s_isLive: Bool
    @NSManaged public var s_timeout: Int64
    @NSManaged public var s_timestamp: Int64
    @NSManaged public var s_uniqueId: String?
    @NSManaged public var s_userId: String?
    @NSManaged public var s_roomSummary: MXRoomSummaryMO?
    
    @discardableResult
    internal static func insert(beaconInfo: MXBeaconInfo,
                                into moc: NSManagedObjectContext) -> MXBeaconInfoMO {
        let model = MXBeaconInfoMO(context: moc)

        model.update(withBeaconInfo: beaconInfo)

        return model
    }
    
    internal func update(withBeaconInfo beaconInfo: MXBeaconInfo) {
        
        s_userId = beaconInfo.userId
        s_uniqueId = beaconInfo.uniqueId
        s_description = beaconInfo.desc
        s_timeout = Int64(beaconInfo.timeout)
        s_isLive = beaconInfo.isLive
        s_timestamp = Int64(beaconInfo.timestamp)
    }
}

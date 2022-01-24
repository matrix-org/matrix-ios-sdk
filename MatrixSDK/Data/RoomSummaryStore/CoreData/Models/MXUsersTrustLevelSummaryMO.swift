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

@objc(MXUsersTrustLevelSummaryMO)
public class MXUsersTrustLevelSummaryMO: NSManagedObject {

    internal static func typedFetchRequest() -> NSFetchRequest<MXUsersTrustLevelSummaryMO> {
        return NSFetchRequest<MXUsersTrustLevelSummaryMO>(entityName: entityName)
    }

    @NSManaged public var s_usersCount: Int32
    @NSManaged public var s_trustedUsersCount: Int32
    @NSManaged public var s_devicesCount: Int32
    @NSManaged public var s_trustedDevicesCount: Int32
    
    @discardableResult
    internal static func insert(roomUsersTrustLevelSummary usersTrustLevelSummary: MXUsersTrustLevelSummary,
                                into moc: NSManagedObjectContext) -> MXUsersTrustLevelSummaryMO {
        let model = MXUsersTrustLevelSummaryMO(context: moc)
        
        model.update(withUsersTrustLevelSummary: usersTrustLevelSummary)
        
        return model
    }
    
    internal func update(withUsersTrustLevelSummary usersTrustLevelSummary: MXUsersTrustLevelSummary) {
        s_usersCount = Int32(usersTrustLevelSummary.trustedUsersProgress.totalUnitCount)
        s_trustedUsersCount = Int32(usersTrustLevelSummary.trustedUsersProgress.completedUnitCount)
        s_devicesCount = Int32(usersTrustLevelSummary.trustedDevicesProgress.totalUnitCount)
        s_trustedDevicesCount = Int32(usersTrustLevelSummary.trustedDevicesProgress.completedUnitCount)
    }
    
}

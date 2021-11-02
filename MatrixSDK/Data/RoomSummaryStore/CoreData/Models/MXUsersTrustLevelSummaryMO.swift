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

    @NSManaged public var s_usersCount: Int16
    @NSManaged public var s_trustedUsersCount: Int16
    @NSManaged public var s_devicesCount: Int16
    @NSManaged public var s_trustedDevicesCount: Int16
    
    @discardableResult
    internal static func insert(roomUsersTrustLevelSummary usersTrustLevelSummary: MXUsersTrustLevelSummary,
                                into moc: NSManagedObjectContext) -> MXUsersTrustLevelSummaryMO {
        let model = MXUsersTrustLevelSummaryMO(context: moc)
        
        model.s_usersCount = Int16(usersTrustLevelSummary.trustedUsersProgress.totalUnitCount)
        model.s_trustedUsersCount = Int16(usersTrustLevelSummary.trustedUsersProgress.completedUnitCount)
        model.s_devicesCount = Int16(usersTrustLevelSummary.trustedDevicesProgress.totalUnitCount)
        model.s_trustedDevicesCount = Int16(usersTrustLevelSummary.trustedDevicesProgress.completedUnitCount)
        
        return model
    }
    
}

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

@objc(MXUsersTrustLevelSummaryModel)
public class MXUsersTrustLevelSummaryModel: NSManagedObject {

    private enum Constants {
        static let entityName: String = "MXUsersTrustLevelSummaryModel"
    }
    
    internal static func typedFetchRequest() -> NSFetchRequest<MXUsersTrustLevelSummaryModel> {
        return NSFetchRequest<MXUsersTrustLevelSummaryModel>(entityName: Constants.entityName)
    }

    @NSManaged public var usersCount: Int16
    @NSManaged public var trustedUsersCount: Int16
    @NSManaged public var devicesCount: Int16
    @NSManaged public var trustedDevicesCount: Int16
    
    internal static func from(roomUsersTrustLevelSummary usersTrustLevelSummary: MXUsersTrustLevelSummary,
                              in managedObjectContext: NSManagedObjectContext) -> MXUsersTrustLevelSummaryModel {
        guard let model = NSEntityDescription.insertNewObject(forEntityName: Constants.entityName,
                                                              into: managedObjectContext) as? MXUsersTrustLevelSummaryModel else {
            fatalError("[MXUsersTrustLevelSummaryModel] from: could not initialize new model")
        }
        
        model.usersCount = Int16(usersTrustLevelSummary.trustedUsersProgress.totalUnitCount)
        model.trustedUsersCount = Int16(usersTrustLevelSummary.trustedUsersProgress.completedUnitCount)
        model.devicesCount = Int16(usersTrustLevelSummary.trustedDevicesProgress.totalUnitCount)
        model.trustedDevicesCount = Int16(usersTrustLevelSummary.trustedDevicesProgress.completedUnitCount)
        
        return model
    }
    
}

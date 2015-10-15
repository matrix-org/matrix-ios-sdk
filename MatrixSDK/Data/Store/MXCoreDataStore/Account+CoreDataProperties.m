//
//  Account+CoreDataProperties.m
//  MatrixSDK
//
//  Created by Emmanuel ROHEE on 14/10/15.
//  Copyright © 2015 matrix.org. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

#import "Account+CoreDataProperties.h"

@implementation Account (CoreDataProperties)

@dynamic eventStreamToken;
@dynamic homeServer;
@dynamic userAvatarUrl;
@dynamic userDisplayName;
@dynamic userId;
@dynamic version;
@dynamic rooms;

@end

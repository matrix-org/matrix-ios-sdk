//
//  MXEventEntity+CoreDataProperties.m
//  MatrixSDK
//
//  Created by Emmanuel ROHEE on 14/10/15.
//  Copyright © 2015 matrix.org. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

#import "MXEventEntity+CoreDataProperties.h"

@implementation MXEventEntity (CoreDataProperties)

@dynamic eventId;
@dynamic type;
@dynamic roomId;
@dynamic sender;
@dynamic userId;
@dynamic prevContent;
@dynamic content;
@dynamic stateKey;
@dynamic originServerTs;
@dynamic redacts;
@dynamic redactedBecause;
@dynamic ageLocalTs;

@end

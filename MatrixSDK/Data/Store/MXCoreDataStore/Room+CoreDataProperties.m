//
//  Room+CoreDataProperties.m
//  MatrixSDK
//
//  Created by Emmanuel ROHEE on 14/10/15.
//  Copyright © 2015 matrix.org. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

#import "Room+CoreDataProperties.h"

@implementation Room (CoreDataProperties)

@dynamic hasReachedHomeServerPaginationEnd;
@dynamic paginationToken;
@dynamic roomId;
@dynamic messages;
@dynamic state;

@end

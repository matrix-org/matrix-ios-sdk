//
//  MXEventEntity+CoreDataProperties.h
//  MatrixSDK
//
//  Created by Emmanuel ROHEE on 14/10/15.
//  Copyright © 2015 matrix.org. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

#import "MXEventEntity.h"

NS_ASSUME_NONNULL_BEGIN

@interface MXEventEntity (CoreDataProperties)

@property (nullable, nonatomic, retain) NSString *eventId;
@property (nullable, nonatomic, retain) NSString *type;
@property (nullable, nonatomic, retain) NSString *roomId;
@property (nullable, nonatomic, retain) NSString *sender;
@property (nullable, nonatomic, retain) NSString *userId;
@property (nullable, nonatomic, retain) id prevContent;
@property (nullable, nonatomic, retain) id content;
@property (nullable, nonatomic, retain) NSString *stateKey;
@property (nullable, nonatomic, retain) NSNumber *originServerTs;
@property (nullable, nonatomic, retain) NSString *redacts;
@property (nullable, nonatomic, retain) id redactedBecause;
@property (nullable, nonatomic, retain) NSNumber *ageLocalTs;

@end

NS_ASSUME_NONNULL_END

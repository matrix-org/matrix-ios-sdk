//
//  Account+CoreDataProperties.h
//  MatrixSDK
//
//  Created by Emmanuel ROHEE on 14/10/15.
//  Copyright © 2015 matrix.org. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

#import "Account.h"

NS_ASSUME_NONNULL_BEGIN

@interface Account (CoreDataProperties)

@property (nullable, nonatomic, retain) NSString *eventStreamToken;
@property (nullable, nonatomic, retain) NSString *homeServer;
@property (nullable, nonatomic, retain) NSString *userAvatarUrl;
@property (nullable, nonatomic, retain) NSString *userDisplayName;
@property (nullable, nonatomic, retain) NSString *userId;
@property (nullable, nonatomic, retain) NSNumber *version;
@property (nullable, nonatomic, retain) NSSet<NSManagedObject *> *rooms;

@end

@interface Account (CoreDataGeneratedAccessors)

- (void)addRoomsObject:(NSManagedObject *)value;
- (void)removeRoomsObject:(NSManagedObject *)value;
- (void)addRooms:(NSSet<NSManagedObject *> *)values;
- (void)removeRooms:(NSSet<NSManagedObject *> *)values;

@end

NS_ASSUME_NONNULL_END

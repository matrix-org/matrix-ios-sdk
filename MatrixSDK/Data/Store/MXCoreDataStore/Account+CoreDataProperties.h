/*
 Copyright 2015 OpenMarket Ltd

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "Account.h"

NS_ASSUME_NONNULL_BEGIN

@interface Account (CoreDataProperties)

@property (nullable, nonatomic, retain) NSString *eventStreamToken;
@property (nullable, nonatomic, retain) NSString *homeServer;
@property (nullable, nonatomic, retain) NSString *userAvatarUrl;
@property (nullable, nonatomic, retain) NSString *userDisplayName;
@property (nullable, nonatomic, retain) NSString *userId;
@property (nullable, nonatomic, retain) NSNumber *version;
@property (nullable, nonatomic, retain) NSString *accessToken;
@property (nullable, nonatomic, retain) NSSet<Room *> *rooms;

@end

@interface Account (CoreDataGeneratedAccessors)

- (void)addRoomsObject:(Room *)value;
- (void)removeRoomsObject:(Room *)value;
- (void)addRooms:(NSSet<Room *> *)values;
- (void)removeRooms:(NSSet<Room *> *)values;

@end

NS_ASSUME_NONNULL_END

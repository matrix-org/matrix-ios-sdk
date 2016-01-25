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

#import "MXCoreDataEvent.h"

#ifdef MXCOREDATA_STORE

NS_ASSUME_NONNULL_BEGIN

@interface MXCoreDataEvent (CoreDataProperties)

@property (nullable, nonatomic, retain) NSNumber *ageLocalTs;
@property (nullable, nonatomic, retain) id content;
@property (nullable, nonatomic, retain) NSString *eventId;
@property (nullable, nonatomic, retain) NSNumber *originServerTs;
@property (nullable, nonatomic, retain) id prevContent;
@property (nullable, nonatomic, retain) id redactedBecause;
@property (nullable, nonatomic, retain) NSString *redacts;
@property (nullable, nonatomic, retain) NSString *roomId;
@property (nullable, nonatomic, retain) NSString *sender;
@property (nullable, nonatomic, retain) NSString *stateKey;
@property (nullable, nonatomic, retain) NSString *type;
@property (nullable, nonatomic, retain) NSString *userId;
@property (nullable, nonatomic, retain) MXCoreDataRoom *room;

@end

NS_ASSUME_NONNULL_END

#endif // MXCOREDATA_STORE

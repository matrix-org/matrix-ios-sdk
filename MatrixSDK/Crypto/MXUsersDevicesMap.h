/*
 Copyright 2016 OpenMarket Ltd

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

#import <Foundation/Foundation.h>

/**
 `MXUsersDevicesInfoMap` is an abstract class to extract data from map of map
  where the 1st map keys are userIds and 2nd map keys are deviceId.
 */
@interface MXUsersDevicesMap<__covariant ObjectType> : NSObject <NSCopying, NSCoding>

/**
 Constructor from an exisiting map.
 */
- (instancetype)initWithMap:(NSDictionary<NSString*, NSDictionary<NSString*, ObjectType>*>*)map;

/**
 The device keys as returned by the homeserver: a map of a map (userId -> deviceId -> Object).
 */
@property (nonatomic) NSDictionary<NSString* /* userId */,
                            NSDictionary<NSString* /* deviceId */, ObjectType>*> *map;

/**
 Helper methods to extract information from 'map'.
 */
- (NSArray<NSString*>*)userIds;
- (NSArray<NSString*>*)deviceIdsForUser:(NSString*)userId;
- (ObjectType)objectForDevice:(NSString*)deviceId forUser:(NSString*)userId;

/**
 Feed helper method.
 */
- (void)setObject:(ObjectType)object forUser:(NSString*)userId andDevice:(NSString*)deviceId;
- (void)setObjects:(NSDictionary<NSString* /* deviceId */, ObjectType>*)objectsPerDevices forUser:(NSString*)userId;

@end


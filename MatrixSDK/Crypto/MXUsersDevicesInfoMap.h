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

#import "MXJSONModel.h"

#import "MXDeviceInfo.h"

/**
 `MXUsersDevicesInfoMap` helps to extract data from device keys sent by an homeserver.
 */
@interface MXUsersDevicesInfoMap : MXJSONModel <NSCopying>

/**
 The device keys as returned by the homeserver: a map of a map (userId -> deviceId -> MXDeviceInfo).
 */
@property (nonatomic) NSDictionary<NSString* /* userId */,
                            NSDictionary<NSString* /* deviceId */, MXDeviceInfo*>*> *map;

/**
 Helper methods to extract information from 'map'.
 */
- (NSArray<NSString*>*)userIds;
- (NSArray<NSString*>*)deviceIdsForUser:(NSString*)userId;
- (MXDeviceInfo*)deviceInfoForDevice:(NSString*)deviceId forUser:(NSString*)userId;

/**
 Feed helper method.
 */
- (void)setDeviceInfo:(MXDeviceInfo*)deviceInfo forUser:(NSString*)userId;
- (void)setDevicesInfo:(NSDictionary<NSString* /* deviceId */, MXDeviceInfo*>*)devicesInfo forUser:(NSString*)userId;

@end


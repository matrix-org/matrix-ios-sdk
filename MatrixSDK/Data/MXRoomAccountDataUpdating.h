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

#import <Foundation/Foundation.h>

@class MXRoom;
@class MXEvent;

/**
 The `MXRoomAccountDataUpdating` allows delegation of the update of room account data.
 */
@protocol MXRoomAccountDataUpdating <NSObject>

/**
 Called to update the room account data on received state events.

 @param room the room of whom account data should be updated.
 @param stateEvents state events that may change the room account data.
 */
- (void)updateAccountDataForRoom:(MXRoom *)room
                 withStateEvents:(NSArray<MXEvent*> *)stateEvents;

/**
 Called to update the room account data if required in need of virtual rooms.

 @param room the room of whom account data should be updated.
 @param nativeRoomId native room id for the virtual room.
 @param completion Block will be called at the end of the process. With a flag whether the room account data has been updated.
 */
- (void)updateAccountDataIfRequiredForRoom:(MXRoom *)room
                          withNativeRoomId:(NSString *)nativeRoomId
                                completion:(void(^)(BOOL updated, NSError *error))completion;

@end

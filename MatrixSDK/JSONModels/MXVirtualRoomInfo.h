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
#import "MXJSONModel.h"

extern NSString* _Nonnull const kRoomIsVirtualJSONKey;
extern NSString* _Nonnull const kRoomNativeRoomIdJSONKey;

NS_ASSUME_NONNULL_BEGIN

@interface MXVirtualRoomInfo : MXJSONModel

/**
 Flag to indicate whether the room is a virtual room.
 */
@property (nonatomic, readonly) BOOL isVirtual;

/**
 Native room id if the room is virtual. Only available if `isVirtual` is YES.
 */
@property (nonatomic, readonly, nullable) NSString *nativeRoomId;

@end

NS_ASSUME_NONNULL_END

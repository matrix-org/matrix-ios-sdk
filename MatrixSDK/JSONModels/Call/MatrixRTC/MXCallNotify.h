// 
// Copyright 2024 The Matrix.org Foundation C.I.C
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
#import "MXMentions.h"

NS_ASSUME_NONNULL_BEGIN

/**
 `MXCallNotify` represents a push notification for a MatrixRTC call,
 describing how the user should be notified about the call.
 */
@interface MXCallNotify : MXJSONModel

/**
 The application that is running the MatrixRTC session. `m.call` represents a VoIP call.
 */
@property (nonatomic) NSString *application;

/**
 Information about who should be notified in the room.
 */
@property (nonatomic) MXMentions *mentions;

/**
 Whether the call should ring or deliver a notification.
 */
@property (nonatomic) NSString *notifyType;

/**
 A unique identifier for the call that is running. Present for an application type of `m.call`.
 */
@property (nonatomic, nullable) NSString *callID;

@end

NS_ASSUME_NONNULL_END

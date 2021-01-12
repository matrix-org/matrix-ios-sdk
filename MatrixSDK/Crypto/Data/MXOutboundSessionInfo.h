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

#import "MXTools.h"
#import "MXCrypto_Private.h"

@interface MXOutboundSessionInfo : NSObject
{
    // When the session was created
    NSDate  *creationTime;
}

- (instancetype)initWithSession:(OLMOutboundGroupSession *)session;

- (instancetype)initWithSession:(OLMOutboundGroupSession *)session creationTime:(NSDate *)creationTime;

/**
 Check if it's time to rotate the session.

 @param rotationPeriodMsgs the max number of encryptions before rotating.
 @param rotationPeriodMs the max duration of an encryption session before rotating.
 @return YES if rotation is needed.
 */
- (BOOL)needsRotation:(NSUInteger)rotationPeriodMsgs rotationPeriodMs:(NSUInteger)rotationPeriodMs;

/**
 Determine if this session has been shared with devices which it shouldn't
 have been.

 @param devicesInRoom userId -> {deviceId -> object} devices we should shared the session with.
 @return YES if we have shared the session with devices which aren't in devicesInRoom.
 */
- (BOOL)sharedWithTooManyDevices:(MXUsersDevicesMap<MXDeviceInfo *> *)devicesInRoom;

/**
 The id of the session
 */
@property (nonatomic, readonly) NSString *sessionId;

/**
 The related session
 */
@property (nonatomic, readonly) OLMOutboundGroupSession *session;

/**
 Number of times this session has been used
 */
@property (nonatomic) NSUInteger useCount;

/**
 If a share operation is in progress, the corresponding http request
 */
@property (nonatomic) MXHTTPOperation* shareOperation;

/**
 Devices with which we have shared the session key
 userId -> {deviceId -> msgindex}
 */
@property (nonatomic) MXUsersDevicesMap<NSNumber*> *sharedWithDevices;

@end

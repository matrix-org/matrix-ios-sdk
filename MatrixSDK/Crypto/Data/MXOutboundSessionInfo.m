// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

#import "MXOutboundSessionInfo.h"
#import "MXOlmOutboundGroupSession.h"

@implementation MXOutboundSessionInfo

- (instancetype)initWithSession:(MXOlmOutboundGroupSession *)session
{
    self = [super init];
    if (self)
    {
        _sessionId = session.sessionId;
        _session = session;
        creationTime = session.creationDate;
        _sharedWithDevices = [[MXUsersDevicesMap alloc] init];
    }
    return self;
}

- (BOOL)needsRotation:(NSUInteger)rotationPeriodMsgs rotationPeriodMs:(NSUInteger)rotationPeriodMs
{
    BOOL needsRotation = NO;
    NSUInteger sessionLifetime = [[NSDate date] timeIntervalSinceDate:creationTime] * 1000;

    if (_useCount >= rotationPeriodMsgs || sessionLifetime >= rotationPeriodMs)
    {
        MXLogDebug(@"[MXOutboundSessionInfo] Rotating megolm session after %tu messages, %tu ms", _useCount, sessionLifetime);
        needsRotation = YES;
    }

    return needsRotation;
}

- (BOOL)sharedWithTooManyDevices:(MXUsersDevicesMap<MXDeviceInfo *> *)devicesInRoom
{
    for (NSString *userId in _sharedWithDevices.userIds)
    {
        if (![devicesInRoom deviceIdsForUser:userId])
        {
            MXLogDebug(@"[MXOutboundSessionInfo] Starting new session because we shared with %@",  userId);
            return YES;
        }

        for (NSString *deviceId in [_sharedWithDevices deviceIdsForUser:userId])
        {
            if (! [devicesInRoom objectForDevice:deviceId forUser:userId])
            {
                MXLogDebug(@"[MXOutboundSessionInfo] Starting new session because we shared with %@:%@", userId, deviceId);
                return YES;
            }
        }
    }

    return NO;
}

@end

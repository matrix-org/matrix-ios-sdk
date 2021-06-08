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

#import "MXOlmOutboundGroupSession.h"

#import <OLMKit/OLMKit.h>

@implementation MXOlmOutboundGroupSession

- (instancetype)initWithSession:(OLMOutboundGroupSession *)session roomId:(NSString *)roomId creationTime:(NSTimeInterval) creationTime
{
    self = [self init];
    if (self)
    {
        _session = session;
        _roomId = roomId;
        _creationTime = creationTime;
    }
    return self;
}

- (NSString *)sessionId
{
    return _session.sessionIdentifier;
}

- (NSString *)sessionKey
{
    return _session.sessionKey;
}

- (NSUInteger)messageIndex
{
    return _session.messageIndex;
}

- (NSDate *)creationDate
{
    return [NSDate dateWithTimeIntervalSince1970:_creationTime];
}

- (NSString *)encryptMessage:(NSString *)message error:(NSError**)error
{
    return [_session encryptMessage:message error:error];
}

@end

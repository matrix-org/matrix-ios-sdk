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

#import "MXOlmInboundGroupSession.h"

#ifdef MX_CRYPTO

#import "MXCryptoConstants.h"

@implementation MXOlmInboundGroupSession

- (instancetype)initWithSessionKey:(NSString *)sessionKey
{
    self = [self init];
    if (self)
    {
        _session  = [[OLMInboundGroupSession alloc] initInboundGroupSessionWithSessionKey:sessionKey error:nil];
        if (!_session)
        {
            return nil;
        }
    }
    return self;
}


#pragma mark - import/export
- (MXMegolmSessionData *)exportSessionDataAtMessageIndex:(NSUInteger)messageIndex
{
    MXMegolmSessionData *sessionData;

    NSError *error;
    NSString *sessionKey = [_session exportSessionAtMessageIndex:messageIndex error:&error];

    if (!error)
    {
        sessionData = [[MXMegolmSessionData alloc] init];

        sessionData.senderKey = _senderKey;
        sessionData.senderClaimedKeys = _keysClaimed;
        sessionData.roomId = _roomId;
        sessionData.sessionId = _session.sessionIdentifier;
        sessionData.sessionKey = sessionKey;
        sessionData.algorithm = kMXCryptoMegolmAlgorithm;
    }
    else
    {
        NSLog(@"[MXOlmInboundGroupSession] exportSessionData: Cannot export session with id %@-%@. Error: %@", _session.sessionIdentifier, _senderKey, error);
    }

    return sessionData;
}

- (MXMegolmSessionData *)exportSessionData
{
    return [self exportSessionDataAtMessageIndex:_session.firstKnownIndex];
}

- (instancetype)initWithSessionData:(MXMegolmSessionData *)data
{
    self = [self init];
    if (self)
    {
        NSError *error;
        _session  = [[OLMInboundGroupSession alloc] initInboundGroupSessionWithImportedSession:data.sessionKey error:&error];
        if (!_session)
        {
            NSLog(@"[MXOlmInboundGroupSession] initWithSessionData failed. Error: %@", error);
            return nil;
        }

        _senderKey = data.senderKey;
        _keysClaimed = data.senderClaimedKeys;
        _roomId= data.roomId;
    }
    return self;
}


#pragma mark - NSCoding
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _session = [aDecoder decodeObjectForKey:@"session"];
        _roomId = [aDecoder decodeObjectForKey:@"roomId"];
        _senderKey = [aDecoder decodeObjectForKey:@"senderKey"];
        _keysClaimed = [aDecoder decodeObjectForKey:@"keysClaimed"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_session forKey:@"session"];
    [aCoder encodeObject:_roomId forKey:@"roomId"];
    [aCoder encodeObject:_senderKey forKey:@"senderKey"];
    [aCoder encodeObject:_keysClaimed forKey:@"keysClaimed"];
}

@end

#endif


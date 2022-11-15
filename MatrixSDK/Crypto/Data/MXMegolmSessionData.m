/*
 Copyright 2017 OpenMarket Ltd

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

#import "MXMegolmSessionData.h"
#import "MXSharedHistoryKeyService.h"
#import "MXSDKOptions.h"

@implementation MXMegolmSessionData

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXMegolmSessionData *sessionData = [[MXMegolmSessionData alloc] init];
    if (sessionData)
    {
        MXJSONModelSetString(sessionData.senderKey, JSONDictionary[@"sender_key"]);
        MXJSONModelSetDictionary(sessionData.senderClaimedKeys, JSONDictionary[@"sender_claimed_keys"]);
        MXJSONModelSetString(sessionData.roomId, JSONDictionary[@"room_id"]);
        MXJSONModelSetString(sessionData.sessionId, JSONDictionary[@"session_id"]);
        MXJSONModelSetString(sessionData.sessionKey, JSONDictionary[@"session_key"]);
        if (MXSDKOptions.sharedInstance.enableRoomSharedHistoryOnInvite)
        {
            MXJSONModelSetBoolean(sessionData.sharedHistory, JSONDictionary[kMXSharedHistoryKeyName]);
        }
        MXJSONModelSetString(sessionData.algorithm, JSONDictionary[@"algorithm"]);
        MXJSONModelSetArray(sessionData.forwardingCurve25519KeyChain, JSONDictionary[@"forwarding_curve25519_key_chain"])
        if (JSONDictionary[@"untrusted"])
        {
            MXJSONModelSetBoolean(sessionData.untrusted, JSONDictionary[@"untrusted"]);
        }
        else
        {
            // if "untrusted" is omitted, mark it as trusted
            sessionData.untrusted = NO;
        }
    }

    return sessionData;
}

- (NSDictionary *)JSONDictionary
{
    if (!_senderKey || !_roomId || !_sessionId || !_sessionKey || !_algorithm)
    {
        NSDictionary *details = @{
            @"sender_key": _senderKey ?: @"unknown",
            @"room_id": _roomId ?: @"unknown",
            @"session_id": _sessionId ?: @"unknown",
            @"algorithm": _algorithm ?: @"unknown",
        };
        MXLogErrorDetails(@"[MXMegolmSessionData] JSONDictionary: some properties are missing", details);
        return nil;
    }
    
    return @{
      @"sender_key": _senderKey,
      @"sender_claimed_keys": _senderClaimedKeys ?: @[],
      @"room_id": _roomId,
      @"session_id": _sessionId,
      @"session_key":_sessionKey,
      kMXSharedHistoryKeyName: @(_sharedHistory),
      @"algorithm": _algorithm,
      @"forwarding_curve25519_key_chain": _forwardingCurve25519KeyChain ?: @[],
      @"untrusted": @(_untrusted)
      };
}

- (BOOL)checkFieldsBeforeEncryption
{
    if (!_algorithm)
    {
        MXLogDebug(@"[MXMegolmSessionData] checkFieldsBeforeEncryption: missing algorithm");
        return NO;
    }
    if (!_senderKey)
    {
        MXLogDebug(@"[MXMegolmSessionData] checkFieldsBeforeEncryption: missing senderKey");
        return NO;
    }
    if (!_senderClaimedKeys)
    {
        MXLogDebug(@"[MXMegolmSessionData] checkFieldsBeforeEncryption: missing senderClaimedKeys");
        return NO;
    }
    if (!_sessionKey)
    {
        MXLogDebug(@"[MXMegolmSessionData] checkFieldsBeforeEncryption: missing sessionKey");
        return NO;
    }

    return YES;
}

@end

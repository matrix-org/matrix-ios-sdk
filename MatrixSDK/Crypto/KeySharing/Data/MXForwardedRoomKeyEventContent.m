// 
// Copyright 2022 The Matrix.org Foundation C.I.C
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

#import "MXForwardedRoomKeyEventContent.h"

static NSString* const kJSONKeyAlgorithm = @"algorithm";
static NSString* const kJSONKeyRoomId = @"room_id";
static NSString* const kJSONKeySenderKey = @"sender_key";
static NSString* const kJSONKeySessionId = @"session_id";
static NSString* const kJSONKeySessionKey = @"session_key";
static NSString* const kJSONKeyForwardingCurve25519KeyChain = @"forwarding_curve25519_key_chain";
static NSString* const kJSONKeySenderClaimedEd25519Key = @"sender_claimed_ed25519_key";

@implementation MXForwardedRoomKeyEventContent

#pragma mark - MXJSONModel

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXForwardedRoomKeyEventContent *result = [[MXForwardedRoomKeyEventContent alloc] init];
    MXJSONModelSetString(result.algorithm, JSONDictionary[kJSONKeyAlgorithm]);
    MXJSONModelSetString(result.roomId, JSONDictionary[kJSONKeyRoomId]);
    MXJSONModelSetString(result.sessionId, JSONDictionary[kJSONKeySessionId]);
    MXJSONModelSetString(result.sessionKey, JSONDictionary[kJSONKeySessionKey]);
    MXJSONModelSetString(result.senderKey, JSONDictionary[kJSONKeySenderKey]);
    MXJSONModelSetString(result.senderClaimedEd25519Key, JSONDictionary[kJSONKeySenderClaimedEd25519Key]);
    if (!result.algorithm || !result.roomId || !result.sessionId || !result.sessionKey || !result.senderKey || !result.senderClaimedEd25519Key)
    {
        MXLogError(@"[MXRoomKeyEventContent] modelFromJSON: Key event is missing fields");
        return nil;
    }
    
    MXJSONModelSetArray(result.forwardingCurve25519KeyChain, JSONDictionary[kJSONKeyForwardingCurve25519KeyChain] ?: @[]);
    MXJSONModelSetBoolean(result.sharedHistory, JSONDictionary[kMXSharedHistoryKeyName]);

    return result;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    JSONDictionary[kJSONKeyAlgorithm] = _algorithm;
    JSONDictionary[kJSONKeyRoomId] = _roomId;
    JSONDictionary[kJSONKeySenderKey] = _senderKey;
    JSONDictionary[kJSONKeySessionId] = _sessionId;
    JSONDictionary[kJSONKeySessionKey] = _sessionKey;
    JSONDictionary[kJSONKeyForwardingCurve25519KeyChain] = _forwardingCurve25519KeyChain;
    JSONDictionary[kJSONKeySenderClaimedEd25519Key] = _senderClaimedEd25519Key;
    JSONDictionary[kMXSharedHistoryKeyName] = @(_sharedHistory);
    return JSONDictionary;
}

@end

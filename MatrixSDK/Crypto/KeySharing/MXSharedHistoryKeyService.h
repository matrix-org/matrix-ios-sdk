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

#ifndef MXSharedHistoryKeyService_h
#define MXSharedHistoryKeyService_h

/**
 Name of the field for `sharedHistory` flag when sharing, exporting or backing up keys
 */
FOUNDATION_EXPORT NSString *const kMXSharedHistoryKeyName;

@class MXSharedHistoryKeyRequest;

/**
 Object managing the session keys and responsible for executing key share requests
 */
@protocol MXSharedHistoryKeyService <NSObject>

/**
 Check whether key for a given session (sessionId + senderKey) exists
 */
- (BOOL)hasSharedHistoryForRoomId:(NSString *)roomId
                        sessionId:(NSString *)sessionId
                        senderKey:(NSString *)senderKey;

/**
 Share keys for a given request, containing userId, list of devices and session to share
 */
- (void)shareKeysForRequest:(MXSharedHistoryKeyRequest *)request
                    success:(void(^)(void))success
                    failure:(void(^)(NSError *))failure;

@end

#endif /* MXSharedHistoryKeyService_h */

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

@class OLMOutboundGroupSession;

@interface MXOlmOutboundGroupSession : NSObject

/**
 Initialise the underneath olm inbound group session.
 
 @param session the associated session instance.
 @param roomId The ID room in which this session is used.
 @param creationTime Timestamp of the creation of the session
 */
- (instancetype)initWithSession:(OLMOutboundGroupSession *)session roomId:(NSString *)roomId creationTime:(NSTimeInterval) creationTime;

/**
 The associated olm outbound group session.
 */
@property (nonatomic, readonly) OLMOutboundGroupSession *session;

/**
 the ID of the current session.
 */
@property (nonatomic, readonly) NSString *sessionId;

/**
 the key of the current session.
 */
@property (nonatomic, readonly) NSString *sessionKey;

/**
 the message index of the current session.
 */
@property (nonatomic, readonly) NSUInteger messageIndex;

/**
 The room in which this session is used.
 */
@property (nonatomic, readonly) NSString *roomId;

/**
 Timestamp of the creation of the session
 */
@property (nonatomic, readonly) NSTimeInterval creationTime;

/**
 NSDate related to creationTime.
 */
@property (nonatomic, readonly) NSDate *creationDate;

/**
 Encrypt a given text message using the current session.
 
 @param message text message to be encrypted
 @param error instance of an NSError if an error occured.
 
 @return the encrypted message. Nil if error occured.
 */
- (NSString *)encryptMessage:(NSString *)message error:(NSError**)error;

@end

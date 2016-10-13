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

#import <Foundation/Foundation.h>

#import <OLMKit/OLMKit.h>

/**
 The 'MXOlmInboundGroupSession' class adds more context to a OLMInboundGroupSession
 object.
 
 This allows additional checks. The class implements NSCoding so that the context
 can be stored.
 */
@interface MXOlmInboundGroupSession : NSObject <NSCoding>

/**
 Initialise the underneath olm inbound group session.
 
 @param the session key.
 */
- (instancetype)initWithSessionKey:(NSString*)sessionKey;

/**
 The associated olm inbound group session.
 */
@property (nonatomic, readonly) OLMInboundGroupSession *session;

/**
 The room in which this session is used.
 */
@property (nonatomic) NSString *roomId;

/**
 The base64-encoded curve25519 key of the sender.
 */
@property (nonatomic) NSString *senderKey;

/**
 Other keys the sender claims.
 */
@property (nonatomic) NSDictionary<NSString*, NSString*> *keysClaimed;

@end

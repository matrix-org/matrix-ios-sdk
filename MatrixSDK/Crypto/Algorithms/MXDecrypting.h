/*
 Copyright 2016 OpenMarket Ltd
 Copyright 2020 The Matrix.org Foundation C.I.C

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

#import "MXHTTPOperation.h"
#import "MXEvent.h"
#import "MXDecryptionResult.h"
#import "MXEventDecryptionResult.h"
#import "MXIncomingRoomKeyRequest.h"

@class MXCrypto, MXOlmInboundGroupSession;


@protocol MXDecrypting <NSObject>

/**
 Constructor.

 @param crypto the related 'MXCrypto'.
*/
- (instancetype)initWithCrypto:(MXCrypto*)crypto;

/**
 Check if we have keys to decrypt an event.
 
 @param event the event to decrypt.
 
 @return YES if keys are present.
 */
- (BOOL)hasKeysToDecryptEvent:(MXEvent*)event;

/**
 Decrypt a message.

 @param event the raw event.
 @param timeline the id of the timeline where the event is decrypted. It is used
                 to prevent replay attack. Can be nil.

 @return The decryption result.
 */
- (MXEventDecryptionResult *)decryptEvent:(MXEvent*)event inTimeline:(NSString*)timeline;

/**
 * Handle a key event.
 *
 * @param event the key event.
 */
- (void)onRoomKeyEvent:(MXEvent*)event;

/**
 Notification that a room key has been imported.

 @param session the session data to import.
 */
- (void)didImportRoomKey:(MXOlmInboundGroupSession*)session;

/**
 Determine if we have the keys necessary to respond to a room key request.

 @param keyRequest the key request.
 @return YES if we have the keys and could (theoretically) share them; else NO.
 */
- (BOOL)hasKeysForKeyRequest:(MXIncomingRoomKeyRequest*)keyRequest;

/**
 Send the response to a room key request.

 @param keyRequest the key request.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)shareKeysWithDevice:(MXIncomingRoomKeyRequest*)keyRequest
                                success:(void (^)(void))success
                                failure:(void (^)(NSError *error))failure;
@end

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

#import "MXEvent.h"

@class MXDecryptionResult, MXSession;


@protocol MXDecrypting <NSObject>

/**
 Constructor.

 @param matrixSession the related 'MXSession'.
 */
- (instancetype)initWithMatrixSession:(MXSession*)matrixSession;

/**
 Decrypt a message

 @param event the raw event.
 @param the result error if there is a problem decrypting the event.

 @return the decryption result. Nil if the event referred to an unknown megolm session.
 */
- (MXDecryptionResult*)decryptEvent:(MXEvent*)event error:(NSError**)error;

/**
 * Handle a key event.
 *
 * @param event the key event.
 */
- (void)onRoomKeyEvent:(MXEvent*)event;

@end


/**
 Result of a decryption.
 */
@interface MXDecryptionResult : NSObject

/**
 The decrypted payload (with properties 'type', 'content')
 */
@property (nonatomic) NSDictionary *payload;

/**
 keys that the sender of the event claims ownership of:
 map from key type to base64-encoded key.
 */
@property (nonatomic) NSDictionary *keysClaimed;

/**
 The keys that the sender of the event is known to have ownership of:
 map from key type to base64-encoded key.
 */
@property (nonatomic) NSDictionary *keysProved;

@end


#pragma mark - Base class implementation

/**
 A base class for decryption implementations.
 */
@interface MXDecryptionAlgorithm : NSObject <MXDecrypting>

/**
 The related matrix session.
 */
@property (nonatomic, readonly) MXSession *mxSession;

@end

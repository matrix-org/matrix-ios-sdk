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
#import "MXDecryptionResult.h"

@class MXCrypto, MXMegolmSessionData;


@protocol MXDecrypting <NSObject>

/**
 Constructor.

 @param crypto the related 'MXCrypto'.
*/
- (instancetype)initWithCrypto:(MXCrypto*)crypto;

/**
 Decrypt a message.

 In case of success, the event is updated with clear data.
 In case of failure, event.decryptionError contains the error.

 @param event the raw event.
 @param timeline the id of the timeline where the event is decrypted. It is used
                 to prevent replay attack.

 @return YES if the decryption was successful.
 */
- (BOOL)decryptEvent:(MXEvent*)event inTimeline:(NSString*)timeline;

/**
 * Handle a key event.
 *
 * @param event the key event.
 */
- (void)onRoomKeyEvent:(MXEvent*)event;

/**
 Import a room key.

 @param session the session data to import.
 */
- (void)importRoomKey:(MXMegolmSessionData*)session;

@end

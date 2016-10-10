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

#include "MXRoom.h"

@protocol MXEncrypting <NSObject>

/**
 Constructor.

 @param matrixSession the related 'MXSession'.
 @param roomId the id of the room we will be sending to.
 */
- (instancetype)initWithMatrixSession:(MXSession*)matrixSession andRoom:(NSString*)roomId;

/**
 Encrypt a message event.

 @param content the plaintext event content.
 @param eventType the type of the event.
 @param room the room.

 @return ? @TODO
 */
//- (NSDictionary*)encryptMessage:(NSDictionary*)content ofType:(MXEventTypeString)eventType inRoom:(MXRoom*)room;

/**
 * Encrypt an event content according to the configuration of the room.
 *
 * @param eventContent the content of the event.
 * @param eventType the type of the event.
 * @param room the room the event will be sent.
 *
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance. May be nil if all required materials is already in place.
 */
- (MXHTTPOperation*)encryptEventContent:(NSDictionary*)eventContent eventType:(MXEventTypeString)eventType inRoom:(MXRoom*)room
                                success:(void (^)(NSDictionary *encryptedContent, NSString *encryptedEventType))success
                                failure:(void (^)(NSError *error))failure;

/**
 Called when the membership of a member of the room changes.

 @param event the event causing the change.
 @param member the user whose membership changed.
 @param oldMembership the previous membership.
 */
- (void)onRoomMembership:(MXEvent*)event member:(MXRoomMember*)member oldMembership:(MXMembership)oldMembership;

/**
 Called when a new device announces itself in the room

 @param {string} userId    owner of the device
 @param {string} deviceId  deviceId of the device
 */
- (void)onNewDevice:(NSString*)deviceId forUser:(NSString*)userId;

@end


#pragma mark - Base class implementation

/**
 A base class for encryption implementations.
 */
@interface MXEncryptionAlgorithm : NSObject <MXEncrypting>

/**
 The related matrix session.
 */
@property (nonatomic, readonly) MXSession *mxSession;

/**
 The id of the room we will be sending to.
 */
@property (nonatomic, readonly) NSString *roomId;

@end

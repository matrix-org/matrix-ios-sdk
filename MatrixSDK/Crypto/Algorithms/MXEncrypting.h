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

#import "MXRoom.h"
#import "MXDeviceInfo.h"

@class MXCrypto;

@protocol MXEncrypting <NSObject>

/**
 Constructor.

 @param crypto the related 'MXCrypto'.
 @param roomId the id of the room we will be sending to.
 */
- (instancetype)initWithCrypto:(MXCrypto*)crypto andRoom:(NSString*)roomId;

/**
 Encrypt an event content according to the configuration of the room.

 @param eventContent the content of the event.
 @param eventType the type of the event.
 @param room the room the event will be sent.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance. May be nil if all required materials is already in place.
 */
- (MXHTTPOperation*)encryptEventContent:(NSDictionary*)eventContent eventType:(MXEventTypeString)eventType inRoom:(MXRoom*)room
                                success:(void (^)(NSDictionary *encryptedContent))success
                                failure:(void (^)(NSError *error))failure;

/**
 Called when the membership of a member of the room changes.

 @param userId the user whose membership changed.
 @param oldMembership the previous membership.
 @param newMembership the new membership.
 */
- (void)onRoomMembership:(NSString*)userId oldMembership:(MXMembership)oldMembership newMembership:(MXMembership)newMembership;

/**
 Called when the verification status of a device changes.
 
 @param device the device which the 'verified' property changed.
 @param oldVerified the old verification status.
 */
- (void)onDeviceVerification:(MXDeviceInfo*)device oldVerified:(MXDeviceVerification)oldVerified;

@end

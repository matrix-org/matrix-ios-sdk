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

NS_ASSUME_NONNULL_BEGIN

/**
 Used to identify the type of data when requesting MXKeyProvider
 */
FOUNDATION_EXPORT NSString *const MXRoomLastMessageDataType;

@class MXEvent;
@class MXRoomLastMessageMO;

/**
 `MXRoomLastMessage` is a model class to store some lastMessage properties for room summary objects.
 */
@interface MXRoomLastMessage : NSObject <NSCoding>

/**
 Event identifier of the last message.
 */
@property (nonatomic, copy, readonly) NSString *eventId;

/**
 Timestamp of the last message.
 */
@property (nonatomic, assign, readonly) uint64_t originServerTs;

/**
 Indicates if the last message is encrypted.
 
 @discussion
 An unencrypted message can be sent to an encrypted room.
 When the last message is encrypted, its summary data (lastMessageString, lastMessageAttributedString,
 lastMessageOthers) is stored encrypted in the room summary cache.
 */
@property (nonatomic, assign, readonly) BOOL isEncrypted;

/**
 Indicates if the last message failed to be decrypted.
 */
@property (nonatomic, assign, readonly) BOOL hasDecryptionError;

/**
 Sender of the last message.
 */
@property (nonatomic, copy, readonly) NSString *sender;

/**
 String representation of this last message.
 */
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, copy, nullable) NSAttributedString *attributedText;

/**
 Placeholder to store more information about the last message.
 */
@property (nonatomic, strong, nullable) NSMutableDictionary<NSString*, id<NSCoding>> *others;

- (instancetype)initWithEvent:(MXEvent *)event;

/**
 Returns an archived (possibly encrypted) version of MXRoomLastMessage sensitive data.
 These include:
 - `text`
 - `attributedText`
 - `others`
 */
- (nullable NSData*)sensitiveData;

#pragma mark - CoreData Model

- (instancetype)initWithManagedObject:(MXRoomLastMessageMO *)model;

- (NSComparisonResult)compareOriginServerTs:(MXRoomLastMessage *)otherMessage;

@end

NS_ASSUME_NONNULL_END

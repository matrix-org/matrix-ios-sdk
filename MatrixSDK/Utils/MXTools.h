/*
 Copyright 2014 OpenMarket Ltd
 
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
#import "MXJSONModels.h"

@interface MXTools : NSObject

+ (MXEventTypeString)eventTypeString:(MXEventType)eventType;
+ (MXEventType)eventType:(MXEventTypeString)eventTypeString;

+ (MXMembership)membership:(MXMembershipString)membershipString;

+ (MXPresence)presence:(MXPresenceString)presenceString;
+ (MXPresenceString)presenceString:(MXPresence)presence;

/**
 Generate a random secret key.
 
 @return the secret.
 */
+ (NSString*)generateSecret;

/**
 Removing new line characters from NSString.
 The new line characters are replaced with a space character.
 Only one space is used to replace successive new line characters spaced or not.

 @return the resulting string.
 */
+ (NSString*)stripNewlineCharacters:(NSString *)inputString;


#pragma mark - Strings kinds check

/**
 Regular expressions to search for kinds of strings.
 */
FOUNDATION_EXPORT NSString *const kMXToolsRegexStringForEmailAddress;
FOUNDATION_EXPORT NSString *const kMXToolsRegexStringForMatrixUserIdentifier;
FOUNDATION_EXPORT NSString *const kMXToolsRegexStringForMatrixRoomAlias;
FOUNDATION_EXPORT NSString *const kMXToolsRegexStringForMatrixRoomIdentifier;

/**
 Check whether a string is formatted as an email address.
 
 @return YES if the provided string is formatted as an email.
 */
+ (BOOL)isEmailAddress:(NSString *)inputString;

/**
 Check whether a string is formatted as a matrix user identifier.
 
 @return YES if the provided string is formatted as a matrix user id.
 */
+ (BOOL)isMatrixUserIdentifier:(NSString *)inputString;

/**
 Check whether a string is formatted as a matrix room alias.
 
 @return YES if the provided string is formatted as a matrix room alias.
 */
+ (BOOL)isMatrixRoomAlias:(NSString *)inputString;

/**
 Check whether a string is formatted as a matrix room identifier.
 
 @return YES if the provided string is formatted as a matrix room identifier.
 */
+ (BOOL)isMatrixRoomIdentifier:(NSString *)inputString;

@end

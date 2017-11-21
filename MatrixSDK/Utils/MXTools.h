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

#import "TargetConditionals.h"
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#elif TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#endif

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
 Generate a random transaction id.

 @return the transaction id.
 */
+ (NSString*)generateTransactionId;

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
FOUNDATION_EXPORT NSString *const kMXToolsRegexStringForMatrixEventIdentifier;

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

/**
 Check whether a string is formatted as a matrix event identifier.

 @return YES if the provided string is formatted as a matrix event identifier.
 */
+ (BOOL)isMatrixEventIdentifier:(NSString *)inputString;


#pragma mark - Permalink
/*
 Return a matrix.to permalink to a room.

 @param roomIdOrAlias the id or the alias of the room to link to.
 @return the matrix.to permalink.
 */
+ (NSString*)permalinkToRoom:(NSString*)roomIdOrAlias;

/*
 Return a matrix.to permalink to an event.

 @param eventId the id of the event to link to.
 @param roomIdOrAlias the room the event belongs to.
 @return the matrix.to permalink.
 */
+ (NSString*)permalinkToEvent:(NSString*)eventId inRoom:(NSString*)roomIdOrAlias;

#pragma mark - File

/**
 Round file size.
 */
+ (long long)roundFileSize:(long long)filesize;

/**
 Return file size in string format.
 
 @param fileSize the file size in bytes.
 @param round tells whether the size must be rounded to hide decimal digits
 */
+ (NSString*)fileSizeToString:(long)fileSize round:(BOOL)round;

/**
 Get folder size.
 
 @param folderPath the folder to get size.
 @return folder size in bytes.
 */
+ (long long)folderSize:(NSString *)folderPath;

/**
 List files in folder.
 
 @param folderPath the folder to list files.
 @param isTimeSorted if YES, the files are sorted by creation date from the oldest to the most recent one.
 @param largeFilesFirst if YES move the largest file to the list head (large > 100KB). It can be combined with isTimeSorted.
 @return the list of files by name.
 */
+ (NSArray*)listFiles:(NSString *)folderPath timeSorted:(BOOL)isTimeSorted largeFilesFirst:(BOOL)largeFilesFirst;

/**
 Deduce the file extension from a contentType.
 
 @param contentType the content type.
 @return file extension (extension divider is included).
 */
+ (NSString*)fileExtensionFromContentType:(NSString*)contentType;

#pragma mark - Video processing

/**
 Convert from a video to a MP4 video container.
 
 @discussion
 If the device does not support MP4 file format, the function will use the QuickTime format.
 
 @param videoLocalURL the local path of the video to convert.
 @param success A block object called when the operation succeeded. It returns
 the path of the output video with some metadata.
 @param failure A block object called when the operation failed.
 */
+ (void)convertVideoToMP4:(NSURL*)videoLocalURL
                  success:(void(^)(NSURL *videoLocalURL, NSString *mimetype, CGSize size, double durationInMs))success
                  failure:(void(^)(void))failure;

#pragma mark - JSON Serialisation

/**
 Convert a JSON object (NSArray, NSDictionary) into a JSON string.

 @param jsonObject the object to convert.
 @return the string corresponding to the JSON object.
 */
+ (NSString*)serialiseJSONObject:(id)jsonObject;

/**
 Convert back a string into a JSON object.

 @param jsonString the string corresponding to the JSON object.
 @return a JSON object.
 */
+ (id)deserialiseJSONString:(NSString*)jsonString;

@end

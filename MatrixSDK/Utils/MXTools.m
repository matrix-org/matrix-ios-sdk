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
#import "MXTools.h"

#import <MobileCoreServices/MobileCoreServices.h>

#import "MXEnumConstants.h"

#pragma mark - Constant definition
NSString *const kMXToolsRegexStringForEmailAddress          = @"[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}";
NSString *const kMXToolsRegexStringForMatrixUserIdentifier  = @"@[A-Z0-9._=-]+:[A-Z0-9.-]+\\.[A-Z]{2,}";
NSString *const kMXToolsRegexStringForMatrixRoomAlias       = @"#[A-Z0-9._%#+-]+:[A-Z0-9.-]+\\.[A-Z]{2,}";
NSString *const kMXToolsRegexStringForMatrixRoomIdentifier  = @"![A-Z0-9]+:[A-Z0-9.-]+\\.[A-Z]{2,}";
NSString *const kMXToolsRegexStringForMatrixEventIdentifier = @"\\$[A-Z0-9]+:[A-Z0-9.-]+\\.[A-Z]{2,}";


#pragma mark - MXTools static private members
// Mapping from MXEventTypeString to MXEventType
static NSDictionary*eventTypesMap;

static NSRegularExpression *isEmailAddressRegex;
static NSRegularExpression *isMatrixUserIdentifierRegex;
static NSRegularExpression *isMatrixRoomAliasRegex;
static NSRegularExpression *isMatrixRoomIdentifierRegex;
static NSRegularExpression *isMatrixEventIdentifierRegex;


@implementation MXTools

+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        eventTypesMap = @{
                          kMXEventTypeStringRoomName: @(MXEventTypeRoomName),
                          kMXEventTypeStringRoomTopic: @(MXEventTypeRoomTopic),
                          kMXEventTypeStringRoomAvatar: @(MXEventTypeRoomAvatar),
                          kMXEventTypeStringRoomMember: @(MXEventTypeRoomMember),
                          kMXEventTypeStringRoomCreate: @(MXEventTypeRoomCreate),
                          kMXEventTypeStringRoomJoinRules: @(MXEventTypeRoomJoinRules),
                          kMXEventTypeStringRoomPowerLevels: @(MXEventTypeRoomPowerLevels),
                          kMXEventTypeStringRoomAliases: @(MXEventTypeRoomAliases),
                          kMXEventTypeStringRoomCanonicalAlias: @(MXEventTypeRoomCanonicalAlias),
                          kMXEventTypeStringRoomEncrypted: @(MXEventTypeRoomEncrypted),
                          kMXEventTypeStringRoomEncryption: @(MXEventTypeRoomEncryption),
                          kMXEventTypeStringRoomHistoryVisibility: @(MXEventTypeRoomHistoryVisibility),
                          kMXEventTypeStringRoomGuestAccess: @(MXEventTypeRoomGuestAccess),
                          kMXEventTypeStringRoomKey: @(MXEventTypeRoomKey),
                          kMXEventTypeStringRoomMessage: @(MXEventTypeRoomMessage),
                          kMXEventTypeStringRoomMessageFeedback: @(MXEventTypeRoomMessageFeedback),
                          kMXEventTypeStringRoomRedaction: @(MXEventTypeRoomRedaction),
                          kMXEventTypeStringRoomThirdPartyInvite: @(MXEventTypeRoomThirdPartyInvite),
                          kMXEventTypeStringRoomTag: @(MXEventTypeRoomTag),
                          kMXEventTypeStringPresence: @(MXEventTypePresence),
                          kMXEventTypeStringTypingNotification: @(MXEventTypeTypingNotification),
                          kMXEventTypeStringNewDevice: @(MXEventTypeNewDevice),
                          kMXEventTypeStringCallInvite: @(MXEventTypeCallInvite),
                          kMXEventTypeStringCallCandidates: @(MXEventTypeCallCandidates),
                          kMXEventTypeStringCallAnswer: @(MXEventTypeCallAnswer),
                          kMXEventTypeStringCallHangup: @(MXEventTypeCallHangup),
                          kMXEventTypeStringReceipt: @(MXEventTypeReceipt)
                          };

        isEmailAddressRegex =  [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", kMXToolsRegexStringForEmailAddress]
                                                                         options:NSRegularExpressionCaseInsensitive error:nil];
        isMatrixUserIdentifierRegex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", kMXToolsRegexStringForMatrixUserIdentifier]
                                                                                options:NSRegularExpressionCaseInsensitive error:nil];
        isMatrixRoomAliasRegex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", kMXToolsRegexStringForMatrixRoomAlias]
                                                                           options:NSRegularExpressionCaseInsensitive error:nil];
        isMatrixRoomIdentifierRegex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", kMXToolsRegexStringForMatrixRoomIdentifier]
                                                                                options:NSRegularExpressionCaseInsensitive error:nil];
        isMatrixEventIdentifierRegex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", kMXToolsRegexStringForMatrixEventIdentifier]
                                                                                 options:NSRegularExpressionCaseInsensitive error:nil];
    });
}

+ (MXEventTypeString)eventTypeString:(MXEventType)eventType
{
    NSArray *matches = [eventTypesMap allKeysForObject:@(eventType)];
    return [matches lastObject];
}

+ (MXEventType)eventType:(MXEventTypeString)eventTypeString
{
    MXEventType eventType = MXEventTypeCustom;

    NSNumber *number = [eventTypesMap objectForKey:eventTypeString];
    if (number)
    {
        eventType = [number unsignedIntegerValue];
    }
    return eventType;
}


+ (MXMembership)membership:(MXMembershipString)membershipString
{
    MXMembership membership = MXMembershipUnknown;
    
    if ([membershipString isEqualToString:kMXMembershipStringInvite])
    {
        membership = MXMembershipInvite;
    }
    else if ([membershipString isEqualToString:kMXMembershipStringJoin])
    {
        membership = MXMembershipJoin;
    }
    else if ([membershipString isEqualToString:kMXMembershipStringLeave])
    {
        membership = MXMembershipLeave;
    }
    else if ([membershipString isEqualToString:kMXMembershipStringBan])
    {
        membership = MXMembershipBan;
    }
    return membership;
}


+ (MXPresence)presence:(MXPresenceString)presenceString
{
    MXPresence presence = MXPresenceUnknown;
    
    // Convert presence string into enum value
    if ([presenceString isEqualToString:kMXPresenceOnline])
    {
        presence = MXPresenceOnline;
    }
    else if ([presenceString isEqualToString:kMXPresenceUnavailable])
    {
        presence = MXPresenceUnavailable;
    }
    else if ([presenceString isEqualToString:kMXPresenceOffline])
    {
        presence = MXPresenceOffline;
    }
    
    return presence;
}

+ (MXPresenceString)presenceString:(MXPresence)presence
{
    MXPresenceString presenceString;
    
    switch (presence)
    {
        case MXPresenceOnline:
            presenceString = kMXPresenceOnline;
            break;
            
        case MXPresenceUnavailable:
            presenceString = kMXPresenceUnavailable;
            break;
            
        case MXPresenceOffline:
            presenceString = kMXPresenceOffline;
            break;
            
        default:
            break;
    }
    
    return presenceString;
}

+ (NSString *)generateSecret
{
    return [[NSProcessInfo processInfo] globallyUniqueString];
}

+ (NSString*)stripNewlineCharacters:(NSString *)inputString
{
    return [inputString stringByReplacingOccurrencesOfString:@" *[\n\r]+[\n\r ]*" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, [inputString length])];
}


#pragma mark - String kinds check

+ (BOOL)isEmailAddress:(NSString *)inputString
{
    return (nil != [isEmailAddressRegex firstMatchInString:inputString options:0 range:NSMakeRange(0, inputString.length)]);
}

+ (BOOL)isMatrixUserIdentifier:(NSString *)inputString
{
    return (nil != [isMatrixUserIdentifierRegex firstMatchInString:inputString options:0 range:NSMakeRange(0, inputString.length)]);
}

+ (BOOL)isMatrixRoomAlias:(NSString *)inputString
{
    return (nil != [isMatrixRoomAliasRegex firstMatchInString:inputString options:0 range:NSMakeRange(0, inputString.length)]);
}

+ (BOOL)isMatrixRoomIdentifier:(NSString *)inputString
{
    return (nil != [isMatrixRoomIdentifierRegex firstMatchInString:inputString options:0 range:NSMakeRange(0, inputString.length)]);
}

+ (BOOL)isMatrixEventIdentifier:(NSString *)inputString
{
    return (nil != [isMatrixEventIdentifierRegex firstMatchInString:inputString options:0 range:NSMakeRange(0, inputString.length)]);
}


#pragma mark - Permalink
+ (NSString *)permalinkToRoom:(NSString *)roomIdOrAlias
{
    return [NSString stringWithFormat:@"%@/#/%@", kMXMatrixDotToUrl, roomIdOrAlias];
}

+ (NSString *)permalinkToEvent:(NSString *)eventId inRoom:(NSString *)roomIdOrAlias
{
    return [NSString stringWithFormat:@"%@/#/%@/%@", kMXMatrixDotToUrl, roomIdOrAlias, eventId];

}

#pragma mark - File

// return an array of files attributes
+ (NSArray*)listAttributesFiles:(NSString *)folderPath
{
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folderPath error:nil];
    NSEnumerator *contentsEnumurator = [contents objectEnumerator];
    
    NSString *file;
    NSMutableArray* res = [[NSMutableArray alloc] init];
    
    while (file = [contentsEnumurator nextObject])
        
    {
        NSString* itemPath = [folderPath stringByAppendingPathComponent:file];
        
        NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:itemPath error:nil];
        
        // is directory
        if ([[fileAttributes objectForKey:NSFileType] isEqual:NSFileTypeDirectory])
            
        {
            [res addObjectsFromArray:[MXTools listAttributesFiles:itemPath]];
        }
        else
            
        {
            NSMutableDictionary* att = [fileAttributes mutableCopy];
            // add the file path
            [att setObject:itemPath forKey:@"NSFilePath"];
            [res addObject:att];
        }
    }
    
    return res;
}

+ (long long)roundFileSize:(long long)filesize
{
    static long long roundedFactor = (100 * 1024);
    static long long smallRoundedFactor = (10 * 1024);
    long long roundedFileSize = filesize;
    
    if (filesize > roundedFactor)
    {
        roundedFileSize = ((filesize + (roundedFactor /2)) / roundedFactor) * roundedFactor;
    }
    else if (filesize > smallRoundedFactor)
    {
        roundedFileSize = ((filesize + (smallRoundedFactor /2)) / smallRoundedFactor) * smallRoundedFactor;
    }
    
    return roundedFileSize;
}

+ (NSString*)fileSizeToString:(long)fileSize round:(BOOL)round
{
    if (fileSize < 0)
    {
        return @"";
    }
    else if (fileSize < 1024)
    {
        return [NSString stringWithFormat:@"%ld bytes", fileSize];
    }
    else if (fileSize < (1024 * 1024))
    {
        if (round)
        {
            return [NSString stringWithFormat:@"%.0f KB", ceil(fileSize / 1024.0)];
        }
        else
        {
            return [NSString stringWithFormat:@"%.2f KB", (fileSize / 1024.0)];
        }
    }
    else
    {
        if (round)
        {
            return [NSString stringWithFormat:@"%.0f MB", ceil(fileSize / 1024.0 / 1024.0)];
        }
        else
        {
            return [NSString stringWithFormat:@"%.2f MB", (fileSize / 1024.0 / 1024.0)];
        }
    }
}

// recursive method to compute the folder content size
+ (long long)folderSize:(NSString *)folderPath
{
    long long folderSize = 0;
    NSArray *fileAtts = [MXTools listAttributesFiles:folderPath];
    
    for(NSDictionary *fileAtt in fileAtts)
    {
        folderSize += [[fileAtt objectForKey:NSFileSize] intValue];
    }
    
    return folderSize;
}

// return the list of files by name
// isTimeSorted : the files are sorted by creation date from the oldest to the most recent one
// largeFilesFirst: move the largest file to the list head (large > 100KB). It can be combined isTimeSorted
+ (NSArray*)listFiles:(NSString *)folderPath timeSorted:(BOOL)isTimeSorted largeFilesFirst:(BOOL)largeFilesFirst
{
    NSArray* attFilesList = [MXTools listAttributesFiles:folderPath];
    
    if (attFilesList.count > 0)
    {
        
        // sorted by timestamp (oldest first)
        if (isTimeSorted)
        {
            NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"NSFileCreationDate" ascending:YES selector:@selector(compare:)];
            attFilesList = [attFilesList sortedArrayUsingDescriptors:@[ sortDescriptor]];
        }
        
        // list the large files first
        if (largeFilesFirst)
        {
            NSMutableArray* largeFilesAttList = [[NSMutableArray alloc] init];
            NSMutableArray* smallFilesAttList = [[NSMutableArray alloc] init];
            
            for (NSDictionary* att in attFilesList)
            {
                if ([[att objectForKey:NSFileSize] intValue] > 100 * 1024)
                {
                    [largeFilesAttList addObject:att];
                }
                else
                {
                    [smallFilesAttList addObject:att];
                }
            }
            
            NSMutableArray* mergedList = [[NSMutableArray alloc] init];
            [mergedList addObjectsFromArray:largeFilesAttList];
            [mergedList addObjectsFromArray:smallFilesAttList];
            attFilesList = mergedList;
        }
        
        // list filenames
        NSMutableArray* res = [[NSMutableArray alloc] init];
        for (NSDictionary* att in attFilesList)
        {
            [res addObject:[att valueForKey:@"NSFilePath"]];
        }
        
        return res;
    }
    else
    {
        return nil;
    }
}


// cache the value to improve the UX.
static NSMutableDictionary *fileExtensionByContentType = nil;

// return the file extension from a contentType
+ (NSString*)fileExtensionFromContentType:(NSString*)contentType
{
    // sanity checks
    if (!contentType || (0 == contentType.length))
    {
        return @"";
    }
    
    NSString* fileExt = nil;
    
    if (!fileExtensionByContentType)
    {
        fileExtensionByContentType  = [[NSMutableDictionary alloc] init];
    }
    
    fileExt = fileExtensionByContentType[contentType];
    
    if (!fileExt)
    {
        fileExt = @"";
        
        // else undefined type
        if ([contentType isEqualToString:@"application/jpeg"])
        {
            fileExt = @".jpg";
        }
        else if ([contentType isEqualToString:@"audio/x-alaw-basic"])
        {
            fileExt = @".alaw";
        }
        else if ([contentType isEqualToString:@"audio/x-caf"])
        {
            fileExt = @".caf";
        }
        else if ([contentType isEqualToString:@"audio/aac"])
        {
            fileExt =  @".aac";
        }
        else
        {
            CFStringRef mimeType = (__bridge CFStringRef)contentType;
            CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType, NULL);
            
            NSString* extension = (__bridge_transfer NSString *)UTTypeCopyPreferredTagWithClass(uti, kUTTagClassFilenameExtension);
            
            CFRelease(uti);
            
            if (extension)
            {
                fileExt = [NSString stringWithFormat:@".%@", extension];
            }
        }
        
        [fileExtensionByContentType setObject:fileExt forKey:contentType];
    }
    
    return fileExt;
}

@end

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

#import "MXRoom.h"

#import "MXSession.h"
#import "MXTools.h"
#import "NSData+MatrixSDK.h"
#import "MXDecryptionResult.h"

#import "MXEncryptedAttachments.h"

#import "MXMediaManager.h"

#import "MXError.h"

NSString *const kMXRoomDidFlushDataNotification = @"kMXRoomDidFlushDataNotification";
NSString *const kMXRoomInitialSyncNotification = @"kMXRoomInitialSyncNotification";
NSString *const kMXRoomDidUpdateUnreadNotification = @"kMXRoomDidUpdateUnreadNotification";

@interface MXRoom ()
{
    /**
     Tell whether the heuristic method used to detect direct room should be applied on this room when the user joins it.
     */
    BOOL shouldCheckDirectStatusOnJoin;
}
@end

@implementation MXRoom
@synthesize mxSession;

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _accountData = [[MXRoomAccountData alloc] init];

        _typingUsers = [NSArray array];
        
        shouldCheckDirectStatusOnJoin = NO;
    }
    
    return self;
}

- (id)initWithRoomId:(NSString *)roomId andMatrixSession:(MXSession *)mxSession2
{
    // Let's the live MXEventTimeline use its default store.
    return [self initWithRoomId:roomId matrixSession:mxSession2 andStore:nil];
}

- (id)initWithRoomId:(NSString *)roomId andMatrixSession:(MXSession *)mxSession2 andStateEvents:(NSArray *)stateEvents andAccountData:(MXRoomAccountData*)accountData
{
    self = [self initWithRoomId:roomId andMatrixSession:mxSession2];
    if (self)
    {
        @autoreleasepool
        {
            [_liveTimeline initialiseState:stateEvents];

            // Report the provided accountData.
            // Allocate a new instance if none, in order to handle room tag events for this room.
            _accountData = accountData ? accountData : [[MXRoomAccountData alloc] init];
            
            // Check whether the room is pending on an invitation.
            if (self.state.membership == MXMembershipInvite)
            {
                // Handle direct flag to decide if it is direct or not
                [self handleInviteDirectFlag];
            }
        }
    }
    return self;
}

- (id)initWithRoomId:(NSString *)roomId matrixSession:(MXSession *)mxSession2 andStore:(id<MXStore>)store
{
    self = [self init];
    if (self)
    {
        _roomId = roomId;
        mxSession = mxSession2;

        if (store)
        {
            _liveTimeline = [[MXEventTimeline alloc] initWithRoom:self initialEventId:nil andStore:store];
        }
        else
        {
            // Let the timeline use the session store
            _liveTimeline = [[MXEventTimeline alloc] initWithRoom:self andInitialEventId:nil];
        }
        
        // Update the stored outgoing messages, by removing the sent messages and tagging as failed the others.
        [self refreshOutgoingMessages];
    }
    return self;
}

#pragma mark - Properties implementation
- (MXRoomState *)state
{
    return _liveTimeline.state;
}

- (void)setPartialTextMessage:(NSString *)partialTextMessage
{
    [mxSession.store storePartialTextMessageForRoom:self.roomId partialTextMessage:partialTextMessage];
    if ([mxSession.store respondsToSelector:@selector(commit)])
    {
        [mxSession.store commit];
    }
}

- (NSString *)partialTextMessage
{
    return [mxSession.store partialTextMessageOfRoom:self.roomId];
}


#pragma mark - Sync
- (void)handleJoinedRoomSync:(MXRoomSync *)roomSync
{
    // Let the live timeline handle live events
    [_liveTimeline handleJoinedRoomSync:roomSync];

    // Handle here ephemeral events (if any)
    for (MXEvent *event in roomSync.ephemeral.events)
    {
        // Report the room id in the event as it is skipped in /sync response
        event.roomId = self.roomId;

        // Handle first typing notifications
        if (event.eventType == MXEventTypeTypingNotification)
        {
            // Typing notifications events are not room messages nor room state events
            // They are just volatile information
            MXJSONModelSetArray(_typingUsers, event.content[@"user_ids"]);

            // Notify listeners
            [_liveTimeline notifyListeners:event direction:MXTimelineDirectionForwards];
        }
        else if (event.eventType == MXEventTypeReceipt)
        {
            [self handleReceiptEvent:event direction:MXTimelineDirectionForwards];
        }
    }
    
    // Store notification counts from unreadNotifications field in /sync response
    [mxSession.store storeNotificationCountOfRoom:self.roomId count:roomSync.unreadNotifications.notificationCount];
    [mxSession.store storeHighlightCountOfRoom:self.roomId count:roomSync.unreadNotifications.highlightCount];
    
    // Notify that unread counts have been sync'ed
    [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomDidUpdateUnreadNotification
                                                        object:self
                                                      userInfo:nil];

    // Handle account data events (if any)
    [self handleAccounDataEvents:roomSync.accountData.events direction:MXTimelineDirectionForwards];
    
    // Check whether the room was pending on an invitation without 'is_direct' flag.
    if (shouldCheckDirectStatusOnJoin)
    {
        shouldCheckDirectStatusOnJoin = NO;
        
        if (self.looksLikeDirect)
        {
            [self setIsDirect:YES withUserId:nil success:nil failure:^(NSError *error) {
                NSLog(@"[MXSession] Failed to tag an joined room as a direct chat");
            }];
        }
    }
}

- (void)handleInvitedRoomSync:(MXInvitedRoomSync *)invitedRoomSync
{
    // Let the live timeline handle live events
    [_liveTimeline handleInvitedRoomSync:invitedRoomSync];
    
    // Handle direct flag to decide if it is direct or not
    [self handleInviteDirectFlag];
}

- (void)handleInviteDirectFlag
{
    // Handle here invite data to decide if it is direct or not
    MXRoomMember *myUser = [self.state memberWithUserId:mxSession.myUser.userId];
    BOOL isDirect = NO;
    
    if (myUser.originalEvent.content[@"is_direct"])
    {
        isDirect = [((NSNumber*)myUser.originalEvent.content[@"is_direct"]) boolValue];
    }
    else
    {
        // If there is no 'is_direct' tag, we'll have to apply heuristics to decide whether to consider it a DM
        // (given it may have come from a client that doesn't know about m.direct).
        shouldCheckDirectStatusOnJoin = YES;
    }
    
    if (isDirect)
    {
        // Mark as direct this room with the invite sender.
        [self setIsDirect:YES withUserId:myUser.originalEvent.sender success:nil failure:^(NSError *error) {
            NSLog(@"[MXSession] Failed to tag an invite as a direct chat");
        }];
    }
}

#pragma mark - Room private account data handling
/**
 Handle private user data events.

 @param accounDataEvents the events to handle.
 @param direction the process direction: MXTimelineDirectionSync or MXTimelineDirectionForwards. MXTimelineDirectionBackwards is not applicable here.
 */
- (void)handleAccounDataEvents:(NSArray<MXEvent*>*)accounDataEvents direction:(MXTimelineDirection)direction
{
    for (MXEvent *event in accounDataEvents)
    {
        [_accountData handleEvent:event];

        // Update the store
        if ([mxSession.store respondsToSelector:@selector(storeAccountDataForRoom:userData:)])
        {
            [mxSession.store storeAccountDataForRoom:self.roomId userData:_accountData];
        }

        // And notify listeners
        [_liveTimeline notifyListeners:event direction:direction];
    }
}


#pragma mark - Stored messages enumerator
- (id<MXEventsEnumerator>)enumeratorForStoredMessages
{
    return [mxSession.store messagesEnumeratorForRoom:self.roomId];
}

- (id<MXEventsEnumerator>)enumeratorForStoredMessagesWithTypeIn:(NSArray *)types ignoreMemberProfileChanges:(BOOL)ignoreProfileChanges
{
    return [mxSession.store messagesEnumeratorForRoom:self.roomId withTypeIn:types ignoreMemberProfileChanges:mxSession.ignoreProfileChangesDuringLastMessageProcessing];
}

- (MXEvent *)lastMessageWithTypeIn:(NSArray*)types
{
    MXEvent *lastMessage;

    @autoreleasepool
    {
        id<MXEventsEnumerator> messagesEnumerator = [mxSession.store messagesEnumeratorForRoom:self.roomId withTypeIn:types ignoreMemberProfileChanges:mxSession.ignoreProfileChangesDuringLastMessageProcessing];
        lastMessage = messagesEnumerator.nextEvent;

        if (!lastMessage)
        {
            // If no messages match the filter contraints, return the last whatever is its type
            lastMessage = self.enumeratorForStoredMessages.nextEvent;
        }
    }

    return lastMessage;
}

- (NSUInteger)storedMessagesCount
{
    NSUInteger storedMessagesCount = 0;

    @autoreleasepool
    {
        // Note: For performance, it may worth to have a dedicated MXStore method to get
        // this value
        storedMessagesCount = self.enumeratorForStoredMessages.remaining;
    }

    return storedMessagesCount;
}


#pragma mark - Room operations
- (MXHTTPOperation*)sendEventOfType:(MXEventTypeString)eventTypeString
                            content:(NSDictionary*)content
                          localEcho:(MXEvent**)localEcho
                            success:(void (^)(NSString *eventId))success
                            failure:(void (^)(NSError *error))failure
{
    MXHTTPOperation *operation;
    
    __block MXEvent *event;
    if (localEcho)
    {
        event = *localEcho;
    }

    void(^onSuccess)(NSString *) = ^(NSString *eventId) {

        if (event)
        {
            // Update the local echo with its actual identifier (by keeping the initial id).
            NSString *localEventId = event.eventId;
            event.eventId = eventId;

            // Update the local echo state (This will trigger kMXEventDidChangeSentStateNotification notification).
            event.sentState = MXEventSentStateSent;

            // Update stored echo.
            // We keep this event here as local echo to handle correctly outgoing messages from multiple devices.
            // The echo will be removed when the corresponding event will come through the server sync.
            [self updateOutgoingMessage:localEventId withOutgoingMessage:event];
        }
        
        if (success)
        {
            success(eventId);
        }
        
    };
    
    void(^onFailure)(NSError *) = ^(NSError *error) {

        if (event)
        {
            // Update the local echo with the error state (This will trigger kMXEventDidChangeSentStateNotification notification).
            event.sentState = MXEventSentStateFailed;
            
            // Update the stored echo.
            [self updateOutgoingMessage:event.eventId withOutgoingMessage:event];
        }
        
        if (failure)
        {
            failure(error);
        }
        
    };
    
    // Check whether the content must be encrypted before sending
    if (mxSession.crypto && self.state.isEncrypted)
    {
        // Check whether the provided content is already encrypted
        if ([eventTypeString isEqualToString:kMXEventTypeStringRoomEncrypted])
        {
            // We handle here the case where we have to resent an encrypted message event.
            if (event)
            {
                // Update the local echo sent state.
                event.sentState = MXEventSentStateSending;
                
                // Update the stored echo.
                [self updateOutgoingMessage:event.eventId withOutgoingMessage:event];
            }
            
            operation = [self _sendEventOfType:eventTypeString content:content success:onSuccess failure:onFailure];
        }
        else
        {
            // Check whether a local echo is required
            if ([eventTypeString isEqualToString:kMXEventTypeStringRoomMessage])
            {
                if (!event)
                {
                    // Add a local echo for this message during the sending process.
                    event = [self addLocalEchoForMessageContent:content withState:MXEventSentStateEncrypting];
                    
                    if (localEcho)
                    {
                        // Return the created event.
                        *localEcho = event;
                    }
                }
                else
                {
                    // Update the local echo state (This will trigger kMXEventDidChangeSentStateNotification notification).
                    event.sentState = MXEventSentStateEncrypting;
                    
                    // Update the stored echo.
                    [self updateOutgoingMessage:event.eventId withOutgoingMessage:event];
                }
            }
            
            operation = [mxSession.crypto encryptEventContent:content withType:eventTypeString inRoom:self success:^(NSDictionary *encryptedContent, NSString *encryptedEventType) {

                if (event)
                {
                    // Encapsulate the resulting event in a fake encrypted event
                    MXEvent *clearEvent = [self fakeRoomMessageEventWithEventId:event.eventId andContent:event.content];

                    event.wireType = encryptedEventType;
                    event.wireContent = encryptedContent;
                    [event setClearData:clearEvent
                             keysProved:@{@"curve25519":mxSession.crypto.deviceCurve25519Key}
                            keysClaimed:nil];

                    // Update the local echo state (This will trigger kMXEventDidChangeSentStateNotification notification).
                    event.sentState = MXEventSentStateSending;

                    // Update stored echo.
                    [self updateOutgoingMessage:event.eventId withOutgoingMessage:event];
                }
  
                // Send the encrypted content
                MXHTTPOperation *operation2 = [self _sendEventOfType:encryptedEventType content:encryptedContent success:onSuccess failure:onFailure];
                if (operation2)
                {
                    // Mutate MXHTTPOperation so that the user can cancel this new operation
                    [operation mutateTo:operation2];
                }
                
            } failure:^(NSError *error) {
                
                NSLog(@"[MXRoom] sendEventOfType: Cannot encrypt event. Error: %@", error);
                
                onFailure(error);
            }];
        }
    }
    else
    {
        // Check whether a local echo is required
        if ([eventTypeString isEqualToString:kMXEventTypeStringRoomMessage])
        {
            if (!event)
            {
                // Add a local echo for this message during the sending process.
                event = [self addLocalEchoForMessageContent:content withState:MXEventSentStateSending];
                
                if (localEcho)
                {
                    // Return the created event.
                    *localEcho = event;
                }
            }
            else
            {
                // Update the local echo state (This will trigger kMXEventDidChangeSentStateNotification notification).
                event.sentState = MXEventSentStateSending;
                
                // Update the stored echo. It will be used to suppress this echo in [self pendingLocalEchoRelatedToEvent];
                [self updateOutgoingMessage:event.eventId withOutgoingMessage:event];
            }
        }
        
        operation = [self _sendEventOfType:eventTypeString content:content success:onSuccess failure:onFailure];
    }
    
    return operation;
}

- (MXHTTPOperation*)_sendEventOfType:(MXEventTypeString)eventTypeString
                            content:(NSDictionary*)content
                            success:(void (^)(NSString *eventId))success
                            failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient sendEventToRoom:self.roomId eventType:eventTypeString content:content success:success failure:failure];
}

- (MXHTTPOperation*)sendStateEventOfType:(MXEventTypeString)eventTypeString
                                 content:(NSDictionary*)content
                                 success:(void (^)(NSString *eventId))success
                                 failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient sendStateEventToRoom:self.roomId eventType:eventTypeString content:content success:success failure:failure];
}

- (MXHTTPOperation*)sendMessageWithContent:(NSDictionary*)content
                                 localEcho:(MXEvent**)localEcho
                                   success:(void (^)(NSString *eventId))success
                                   failure:(void (^)(NSError *error))failure
{
    return [self sendEventOfType:kMXEventTypeStringRoomMessage content:content localEcho:localEcho success:success failure:failure];
}

- (MXHTTPOperation*)sendTextMessage:(NSString*)text
                      formattedText:(NSString*)formattedText
                          localEcho:(MXEvent**)localEcho
                            success:(void (^)(NSString *eventId))success
                            failure:(void (^)(NSError *error))failure
{
    // Prepare the message content
    NSDictionary *msgContent;
    if (!formattedText)
    {
        // This is a simple text message
        msgContent = @{
                       @"msgtype": kMXMessageTypeText,
                       @"body": text
                       };
    }
    else
    {
        // Send the HTML formatted string
        msgContent = @{
                       @"msgtype": kMXMessageTypeText,
                       @"body": text,
                       @"formatted_body": formattedText,
                       @"format": kMXRoomMessageFormatHTML
                       };
    }
    
    return [self sendMessageWithContent:msgContent
                              localEcho:localEcho
                                success:success
                                failure:failure];
}

- (MXHTTPOperation *)sendTextMessage:(NSString *)text
                             success:(void (^)(NSString *))success
                             failure:(void (^)(NSError *))failure
{
    return [self sendTextMessage:text formattedText:nil localEcho:nil success:success failure:failure];
}

- (MXHTTPOperation*)sendEmote:(NSString*)emoteBody
                formattedText:(NSString*)formattedBody
                    localEcho:(MXEvent**)localEcho
                      success:(void (^)(NSString *eventId))success
                      failure:(void (^)(NSError *error))failure
{
    // Prepare the message content
    NSDictionary *msgContent;
    if (!formattedBody)
    {
        // This is a simple text message
        msgContent = @{
                       @"msgtype": kMXMessageTypeEmote,
                       @"body": emoteBody
                       };
    }
    else
    {
        // Send the HTML formatted string
        msgContent = @{
                       @"msgtype": kMXMessageTypeEmote,
                       @"body": emoteBody,
                       @"formatted_body": formattedBody,
                       @"format": kMXRoomMessageFormatHTML
                       };
    }
    
    return [self sendMessageWithContent:msgContent
                              localEcho:localEcho
                                success:success
                                failure:failure];
}

- (MXHTTPOperation*)sendImage:(NSData*)imageData
                withImageSize:(CGSize)imageSize
                     mimeType:(NSString*)mimetype
#if TARGET_OS_IPHONE
                 andThumbnail:(UIImage*)thumbnail
#elif TARGET_OS_OSX
                 andThumbnail:(NSImage*)thumbnail
#endif
                    localEcho:(MXEvent**)localEcho
                      success:(void (^)(NSString *eventId))success
                      failure:(void (^)(NSError *error))failure
{
    // Create a fake operation by default
    MXHTTPOperation *operation = [[MXHTTPOperation alloc] init];
    
    double endRange = 1.0;
    
    // Check whether the content must be encrypted before sending
    if (mxSession.crypto && self.state.isEncrypted) endRange = 0.9;
    
    // Use the uploader id as fake URL for this image data
    // The URL does not need to be valid as the MediaManager will get the data
    // directly from its cache
    // Pass this id in the URL is a nasty trick to retrieve it later
    MXMediaLoader *uploader = [MXMediaManager prepareUploaderWithMatrixSession:mxSession initialRange:0 andRange:endRange];
    NSString *fakeMediaManagerURL = uploader.uploadId;
    
    NSString *cacheFilePath = [MXMediaManager cachePathForMediaWithURL:fakeMediaManagerURL andType:mimetype inFolder:self.roomId];
    [MXMediaManager writeMediaData:imageData toFilePath:cacheFilePath];
    
    // Create a fake image name based on imageData to keep the same name for the same image.
    NSString *dataHash = [imageData mx_MD5];
    if (dataHash.length > 7)
    {
        // Crop
        dataHash = [dataHash substringToIndex:7];
    }
    NSString *extension = [MXTools fileExtensionFromContentType:mimetype];
    NSString *filename = [NSString stringWithFormat:@"ima_%@%@", dataHash, extension];
    
    // Prepare the message content for building an echo message
    NSMutableDictionary *msgContent = [@{
                                         @"msgtype": kMXMessageTypeImage,
                                         @"body": filename,
                                         @"url": fakeMediaManagerURL,
                                         @"info": [@{
                                                     @"mimetype": mimetype,
                                                     @"w": @(imageSize.width),
                                                     @"h": @(imageSize.height),
                                                     @"size": @(imageData.length)
                                                     } mutableCopy]
                                         } mutableCopy];
    
    __block MXEvent *event;
    __block id uploaderObserver;
    
    void(^onFailure)(NSError *) = ^(NSError *error) {
        
        // Remove outgoing message when its sent has been cancelled
        if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled)
        {
            [self removeOutgoingMessage:event.eventId];
        }
        else
        {
            // Update the local echo with the error state (This will trigger kMXEventDidChangeSentStateNotification notification).
            event.sentState = MXEventSentStateFailed;
            
            // Update the stored echo.
            [self updateOutgoingMessage:event.eventId withOutgoingMessage:event];
        }
        
        if (uploaderObserver)
        {
            [[NSNotificationCenter defaultCenter] removeObserver:uploaderObserver];
            uploaderObserver = nil;
        }
        
        if (failure)
        {
            failure(error);
        }
        
    };
    
    // Add a local echo for this message during the sending process.
    MXEventSentState initialSentState = (mxSession.crypto && self.state.isEncrypted) ? MXEventSentStateEncrypting : MXEventSentStateUploading;
    event = [self addLocalEchoForMessageContent:msgContent withState:initialSentState];
    
    if (localEcho)
    {
        // Return the created event.
        *localEcho = event;
    }
    
    // Check whether the content must be encrypted before sending
    if (mxSession.crypto && self.state.isEncrypted)
    {
        // Register uploader observer
        uploaderObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXMediaUploadProgressNotification object:uploader queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
            
            if (uploader.statisticsDict)
            {
                NSNumber* progressNumber = [uploader.statisticsDict valueForKey:kMXMediaLoaderProgressValueKey];
                if (progressNumber.floatValue)
                {
                    event.sentState = MXEventSentStateUploading;
                    
                    // Update the stored echo.
                    [self updateOutgoingMessage:event.eventId withOutgoingMessage:event];
                    
                    [[NSNotificationCenter defaultCenter] removeObserver:uploaderObserver];
                    uploaderObserver = nil;
                }
            }
            
        }];
        
        NSURL *localURL = [NSURL URLWithString:cacheFilePath];
        [MXEncryptedAttachments encryptAttachment:uploader mimeType:mimetype localUrl:localURL success:^(NSDictionary *result) {
            
            [msgContent removeObjectForKey:@"url"];
            msgContent[@"file"] = result;
            
            void(^onDidUpload)() = ^{
                
                // Send this content (the sent state of the local echo will be updated, its local storage too).
                MXHTTPOperation *operation2 = [self sendMessageWithContent:msgContent localEcho:&event success:success failure:failure];
                if (operation2)
                {
                    // Mutate MXHTTPOperation so that the user can cancel this new operation
                    [operation mutateTo:operation2];
                }
                
            };
            
            if (!thumbnail)
            {
                onDidUpload();
            }
            else
            {
                // Update the stored echo.
                [self updateOutgoingMessage:event.eventId withOutgoingMessage:event];
                
                MXMediaLoader *thumbUploader = [MXMediaManager prepareUploaderWithMatrixSession:self.mxSession initialRange:0.9 andRange:1];
                
#if TARGET_OS_IPHONE
                NSData *pngImageData = UIImagePNGRepresentation(thumbnail);
#elif TARGET_OS_OSX
                CGImageRef cgRef = [thumbnail CGImageForProposedRect:NULL context:nil hints:nil];
                NSBitmapImageRep *newRep = [[NSBitmapImageRep alloc] initWithCGImage:cgRef];
                [newRep setSize:[thumbnail size]];
                NSData *pngImageData = [newRep representationUsingType:NSPNGFileType properties:@{}];
#endif
                
                [MXEncryptedAttachments encryptAttachment:thumbUploader mimeType:@"image/png" data:pngImageData success:^(NSDictionary *result) {
                    
                    msgContent[@"info"][@"thumbnail_file"] = result;
                    
                    onDidUpload();
                    
                } failure:onFailure];
            }
        } failure:onFailure];
    }
    else
    {
        // Launch the upload to the Matrix Content repository
        [uploader uploadData:imageData filename:filename mimeType:mimetype success:^(NSString *url) {
            
            // Copy the cached image to the actual cacheFile path
            NSString *absoluteURL = [self.mxSession.matrixRestClient urlOfContent:url];
            NSString *actualCacheFilePath = [MXMediaManager cachePathForMediaWithURL:absoluteURL andType:mimetype inFolder:self.roomId];
            NSError *error;
            [[NSFileManager defaultManager] copyItemAtPath:cacheFilePath toPath:actualCacheFilePath error:&error];
            
            // Update the message content with the mxc:// of the media on the homeserver
            msgContent[@"url"] = url;
            
            // Make the final request that posts the image event (the sent state of the local echo will be updated, its local storage too).
            MXHTTPOperation *operation2 = [self sendMessageWithContent:msgContent localEcho:&event success:success failure:onFailure];
            if (operation2)
            {
                // Mutate MXHTTPOperation so that the user can cancel this new operation
                [operation mutateTo:operation2];
            }
            
        } failure:onFailure];
    }
    
    return operation;
}

- (MXHTTPOperation*)sendVideo:(NSURL*)videoLocalURL
#if TARGET_OS_IPHONE
                withThumbnail:(UIImage*)videoThumbnail
#elif TARGET_OS_OSX
                withThumbnail:(NSImage*)videoThumbnail
#endif
                    localEcho:(MXEvent**)localEcho
                      success:(void (^)(NSString *eventId))success
                      failure:(void (^)(NSError *error))failure
{
    // Create a fake operation by default
    MXHTTPOperation *operation = [[MXHTTPOperation alloc] init];
#if TARGET_OS_IPHONE
    NSData *videoThumbnailData = UIImageJPEGRepresentation(videoThumbnail, 0.8);
#elif TARGET_OS_OSX
    CGImageRef cgRef = [videoThumbnail CGImageForProposedRect:NULL context:nil hints:nil];
    NSBitmapImageRep *newRep = [[NSBitmapImageRep alloc] initWithCGImage:cgRef];
    [newRep setSize:[videoThumbnail size]];
    NSData *videoThumbnailData = [newRep representationUsingType:NSJPEGFileType properties: @{NSImageCompressionFactor: @0.8}];
#endif
    
    
    
    // Use the uploader id as fake URL for this image data
    // The URL does not need to be valid as the MediaManager will get the data
    // directly from its cache
    // Pass this id in the URL is a nasty trick to retrieve it later
    MXMediaLoader *thumbUploader = [MXMediaManager prepareUploaderWithMatrixSession:self.mxSession initialRange:0 andRange:0.1];
    NSString *fakeMediaManagerThumbnailURL = thumbUploader.uploadId;
    
    NSString *cacheFilePath = [MXMediaManager cachePathForMediaWithURL:fakeMediaManagerThumbnailURL andType:@"image/jpeg" inFolder:self.roomId];
    [MXMediaManager writeMediaData:videoThumbnailData toFilePath:cacheFilePath];
    
    // Prepare the message content for building an echo message
    NSMutableDictionary *msgContent = [@{
                                         @"msgtype": kMXMessageTypeVideo,
                                         @"body": @"Video",
                                         @"url": fakeMediaManagerThumbnailURL,
                                         @"info": [@{
                                                     @"thumbnail_url": fakeMediaManagerThumbnailURL,
                                                     @"thumbnail_info": @{
                                                             @"mimetype": @"image/jpeg",
                                                             @"w": @(videoThumbnail.size.width),
                                                             @"h": @(videoThumbnail.size.height),
                                                             @"size": @(videoThumbnailData.length)
                                                             }
                                                     } mutableCopy]
                                         } mutableCopy];
    
    __block MXEvent *event;
    __block id uploaderObserver;
    
    void(^onFailure)(NSError *) = ^(NSError *error) {
        
        // Remove outgoing message when its sent has been cancelled
        if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled)
        {
            [self removeOutgoingMessage:event.eventId];
        }
        else
        {
            // Update the local echo with the error state (This will trigger kMXEventDidChangeSentStateNotification notification).
            event.sentState = MXEventSentStateFailed;
            
            // Update the stored echo.
            [self updateOutgoingMessage:event.eventId withOutgoingMessage:event];
        }
        
        if (uploaderObserver)
        {
            [[NSNotificationCenter defaultCenter] removeObserver:uploaderObserver];
            uploaderObserver = nil;
        }
        
        if (failure)
        {
            failure(error);
        }
        
    };
    
    // Add a local echo for this message during the sending process.
    event = [self addLocalEchoForMessageContent:msgContent withState:MXEventSentStatePreparing];
    
    if (localEcho)
    {
        // Return the created event.
        *localEcho = event;
    }
    
    // Before sending data to the server, convert the video to MP4
    [MXTools convertVideoToMP4:videoLocalURL success:^(NSURL *convertedLocalURL, NSString *mimetype, CGSize size, double durationInMs) {
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:convertedLocalURL.path])
        {
            failure(nil);
            return;
        }
        
        // update metadata with result of converter output
        msgContent[@"info"][@"mimetype"] = mimetype;
        msgContent[@"info"][@"w"] = @(size.width);
        msgContent[@"info"][@"h"] = @(size.height);
        msgContent[@"info"][@"duration"] = @(durationInMs);
        
        if (self.mxSession.crypto && self.state.isEncrypted)
        {
            [MXEncryptedAttachments encryptAttachment:thumbUploader mimeType:@"image/jpeg" data:videoThumbnailData success:^(NSDictionary *result) {
                
                // Update thumbnail URL with the actual mxc: URL
                msgContent[@"info"][@"thumbnail_file"] = result;
                [msgContent[@"info"] removeObjectForKey:@"thumbnail_url"];
                
                MXMediaLoader *videoUploader = [MXMediaManager prepareUploaderWithMatrixSession:self.mxSession initialRange:0.1 andRange:1];
                
                // Self-proclaimed, "nasty trick" cargoculted from below...
                // Apply the nasty trick again so that the cell can monitor the upload progress
                msgContent[@"url"] = videoUploader.uploadId;
                
                // Update the local echo state (This will trigger kMXEventDidChangeSentStateNotification notification).
                event.sentState = MXEventSentStateEncrypting;
                
                [self updateOutgoingMessage:event.eventId withOutgoingMessage:event];
                
                // Register video uploader observer in order to trigger sent state change
                uploaderObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXMediaUploadProgressNotification object:videoUploader queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
                    
                    if (videoUploader.statisticsDict)
                    {
                        NSNumber* progressNumber = [videoUploader.statisticsDict valueForKey:kMXMediaLoaderProgressValueKey];
                        if (progressNumber.floatValue)
                        {
                            event.sentState = MXEventSentStateUploading;
                            
                            // Update the stored echo.
                            [self updateOutgoingMessage:event.eventId withOutgoingMessage:event];
                            
                            [[NSNotificationCenter defaultCenter] removeObserver:uploaderObserver];
                            uploaderObserver = nil;
                        }
                    }
                    
                }];
                
                [MXEncryptedAttachments encryptAttachment:videoUploader mimeType:mimetype localUrl:convertedLocalURL success:^(NSDictionary *result) {
                    
                    [msgContent removeObjectForKey:@"url"];
                    msgContent[@"file"] = result;
                    
                    // Send this content (the sent state of the local echo will be updated, its local storage too).
                    MXHTTPOperation *operation2 = [self sendMessageWithContent:msgContent localEcho:&event success:success failure:failure];
                    if (operation2)
                    {
                        // Mutate MXHTTPOperation so that the user can cancel this new operation
                        [operation mutateTo:operation2];
                    }
                    
                } failure:onFailure];
            } failure:onFailure];
        }
        else
        {
            // Upload thumbnail
            [thumbUploader uploadData:videoThumbnailData filename:nil mimeType:@"image/jpeg" success:^(NSString *thumbnailUrl) {
                
                // Upload video
                NSData* videoData = [NSData dataWithContentsOfFile:convertedLocalURL.path];
                if (videoData)
                {
                    // Copy the cached thumbnail to the actual cacheFile path
                    NSString *absoluteURL = [self.mxSession.matrixRestClient urlOfContent:thumbnailUrl];
                    NSString *actualCacheFilePath = [MXMediaManager cachePathForMediaWithURL:absoluteURL andType:@"image/jpeg" inFolder:self.roomId];
                    NSError *error;
                    [[NSFileManager defaultManager] copyItemAtPath:cacheFilePath toPath:actualCacheFilePath error:&error];
                    
                    MXMediaLoader *videoUploader = [MXMediaManager prepareUploaderWithMatrixSession:self.mxSession initialRange:0.1 andRange:0.9];
                    
                    // Create a fake file name based on videoData to keep the same name for the same file.
                    NSString *dataHash = [videoData mx_MD5];
                    if (dataHash.length > 7)
                    {
                        // Crop
                        dataHash = [dataHash substringToIndex:7];
                    }
                    NSString *extension = [MXTools fileExtensionFromContentType:mimetype];
                    NSString *filename = [NSString stringWithFormat:@"video_%@%@", dataHash, extension];
                    msgContent[@"body"] = filename;
                    
                    // Update thumbnail URL with the actual mxc: URL
                    msgContent[@"info"][@"thumbnail_url"] = thumbnailUrl;
                    
                    // Apply the nasty trick again so that the cell can monitor the upload progress
                    msgContent[@"url"] = videoUploader.uploadId;
                    
                    // Update the local echo state (This will trigger kMXEventDidChangeSentStateNotification notification).
                    event.sentState = MXEventSentStateUploading;
                    
                    [self updateOutgoingMessage:event.eventId withOutgoingMessage:event];
                    
                    [videoUploader uploadData:videoData filename:filename mimeType:mimetype success:^(NSString *videoUrl) {
                        
                        // Write the video to the actual cacheFile path
                        NSString *absoluteURL = [self.mxSession.matrixRestClient urlOfContent:videoUrl];
                        NSString *actualCacheFilePath = [MXMediaManager cachePathForMediaWithURL:absoluteURL andType:mimetype inFolder:self.roomId];
                        [MXMediaManager writeMediaData:videoData toFilePath:actualCacheFilePath];
                        
                        // Update video URL with the actual mxc: URL
                        msgContent[@"url"] = videoUrl;
                        
                        // And send the Matrix room message video event to the homeserver (the sent state of the local echo will be updated, its local storage too).
                        MXHTTPOperation *operation2 = [self sendMessageWithContent:msgContent localEcho:&event success:success failure:failure];
                        if (operation2)
                        {
                            // Mutate MXHTTPOperation so that the user can cancel this new operation
                            [operation mutateTo:operation2];
                        }
                        
                    } failure:onFailure];
                }
                else
                {
                    onFailure(nil);
                }
            } failure:onFailure];
        }
    } failure:onFailure];
    
    return operation;
}

- (MXHTTPOperation*)sendFile:(NSURL*)fileLocalURL
                    mimeType:(NSString*)mimeType
                   localEcho:(MXEvent**)localEcho
                     success:(void (^)(NSString *eventId))success
                     failure:(void (^)(NSError *error))failure
{
    // Create a fake operation by default
    MXHTTPOperation *operation = [[MXHTTPOperation alloc] init];
    
    NSData *fileData = [NSData dataWithContentsOfFile:fileLocalURL.path];
    
    // Use the uploader id as fake URL for this file data
    // The URL does not need to be valid as the MediaManager will get the data
    // directly from its cache
    // Pass this id in the URL is a nasty trick to retrieve it later
    MXMediaLoader *uploader = [MXMediaManager prepareUploaderWithMatrixSession:self.mxSession initialRange:0 andRange:1];
    NSString *fakeMediaManagerURL = uploader.uploadId;
    
    NSString *cacheFilePath = [MXMediaManager cachePathForMediaWithURL:fakeMediaManagerURL andType:mimeType inFolder:self.roomId];
    [MXMediaManager writeMediaData:fileData toFilePath:cacheFilePath];
    
    // Create a fake name based on fileData to keep the same name for the same file.
    NSString *dataHash = [fileData mx_MD5];
    if (dataHash.length > 7)
    {
        // Crop
        dataHash = [dataHash substringToIndex:7];
    }
    NSString *extension = [MXTools fileExtensionFromContentType:mimeType];
    NSString *filename = [NSString stringWithFormat:@"file_%@%@", dataHash, extension];
    
    // Prepare the message content for building an echo message
    NSMutableDictionary *msgContent = [@{
                                         @"msgtype": kMXMessageTypeFile,
                                         @"body": filename,
                                         @"url": fakeMediaManagerURL,
                                         @"info": @{
                                                 @"mimetype": mimeType,
                                                 @"size": @(fileData.length)
                                                 }
                                         } mutableCopy];
    
    __block MXEvent *event;
    __block id uploaderObserver;
    
    void(^onFailure)(NSError *) = ^(NSError *error) {
        
        // Remove outgoing message when its sent has been cancelled
        if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled)
        {
            [self removeOutgoingMessage:event.eventId];
        }
        else
        {
            // Update the local echo with the error state (This will trigger kMXEventDidChangeSentStateNotification notification).
            event.sentState = MXEventSentStateFailed;
            
            // Update the stored echo.
            [self updateOutgoingMessage:event.eventId withOutgoingMessage:event];
        }
        
        if (uploaderObserver)
        {
            [[NSNotificationCenter defaultCenter] removeObserver:uploaderObserver];
            uploaderObserver = nil;
        }
        
        if (failure)
        {
            failure(error);
        }
        
    };
    
    // Add a local echo for this message during the sending process.
    MXEventSentState initialSentState = (mxSession.crypto && self.state.isEncrypted) ? MXEventSentStateEncrypting : MXEventSentStateUploading;
    event = [self addLocalEchoForMessageContent:msgContent withState:initialSentState];
    
    if (localEcho)
    {
        // Return the created event.
        *localEcho = event;
    }
    
    if (self.mxSession.crypto && self.state.isEncrypted)
    {
        // Register uploader observer
        uploaderObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXMediaUploadProgressNotification object:uploader queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
            
            if (uploader.statisticsDict)
            {
                NSNumber* progressNumber = [uploader.statisticsDict valueForKey:kMXMediaLoaderProgressValueKey];
                if (progressNumber.floatValue)
                {
                    event.sentState = MXEventSentStateUploading;
                    
                    // Update the stored echo.
                    [self updateOutgoingMessage:event.eventId withOutgoingMessage:event];
                    
                    [[NSNotificationCenter defaultCenter] removeObserver:uploaderObserver];
                    uploaderObserver = nil;
                }
            }
            
        }];
        
        [MXEncryptedAttachments encryptAttachment:uploader mimeType:mimeType localUrl:fileLocalURL success:^(NSDictionary *result) {
            
            [msgContent removeObjectForKey:@"url"];
            msgContent[@"file"] = result;
            
            MXHTTPOperation *operation2 = [self sendMessageWithContent:msgContent localEcho:&event success:success failure:failure];
            if (operation2)
            {
                // Mutate MXHTTPOperation so that the user can cancel this new operation
                [operation mutateTo:operation2];
            }
            
        } failure:onFailure];
    }
    else
    {
        // Launch the upload to the Matrix Content repository
        [uploader uploadData:fileData filename:filename mimeType:mimeType success:^(NSString *url) {
            
            // Copy the cached file to the actual cacheFile path
            NSString *absoluteURL = [self.mxSession.matrixRestClient urlOfContent:url];
            NSString *actualCacheFilePath = [MXMediaManager cachePathForMediaWithURL:absoluteURL andType:mimeType inFolder:self.roomId];
            NSError *error;
            [[NSFileManager defaultManager] copyItemAtPath:cacheFilePath toPath:actualCacheFilePath error:&error];
            
            // Update the message content with the mxc:// of the media on the homeserver
            msgContent[@"url"] = url;
            
            // Make the final request that posts the image event
            MXHTTPOperation *operation2 = [self sendMessageWithContent:msgContent localEcho:&event success:success failure:onFailure];
            if (operation2)
            {
                // Mutate MXHTTPOperation so that the user can cancel this new operation
                [operation mutateTo:operation2];
            }
            
        } failure:onFailure];
    }
    
    return operation;
}

- (MXHTTPOperation*)setTopic:(NSString*)topic
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient setRoomTopic:self.roomId topic:topic success:success failure:failure];
}

- (MXHTTPOperation*)setAvatar:(NSString*)avatar
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient setRoomAvatar:self.roomId avatar:avatar success:success failure:failure];
}


- (MXHTTPOperation*)setName:(NSString*)name
                    success:(void (^)())success
                    failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient setRoomName:self.roomId name:name success:success failure:failure];
}

- (MXHTTPOperation *)setHistoryVisibility:(MXRoomHistoryVisibility)historyVisibility
                                  success:(void (^)())success
                                  failure:(void (^)(NSError *))failure
{
    return [mxSession.matrixRestClient setRoomHistoryVisibility:self.roomId historyVisibility:historyVisibility success:success failure:failure];
}

- (MXHTTPOperation*)setJoinRule:(MXRoomJoinRule)joinRule
                        success:(void (^)())success
                        failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient setRoomJoinRule:self.roomId joinRule:joinRule success:success failure:failure];
}

- (MXHTTPOperation*)setGuestAccess:(MXRoomGuestAccess)guestAccess
                           success:(void (^)())success
                           failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient setRoomGuestAccess:self.roomId guestAccess:guestAccess success:success failure:failure];
}

- (MXHTTPOperation*)setDirectoryVisibility:(MXRoomDirectoryVisibility)directoryVisibility
                                   success:(void (^)())success
                                   failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient setRoomDirectoryVisibility:self.roomId directoryVisibility:directoryVisibility success:success failure:failure];
}

- (MXHTTPOperation*)addAlias:(NSString *)roomAlias
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient addRoomAlias:self.roomId alias:roomAlias success:success failure:failure];
}

- (MXHTTPOperation*)removeAlias:(NSString *)roomAlias
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient removeRoomAlias:roomAlias success:success failure:failure];
}

- (MXHTTPOperation*)setCanonicalAlias:(NSString *)canonicalAlias
                              success:(void (^)())success
                              failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient setRoomCanonicalAlias:self.roomId canonicalAlias:canonicalAlias success:success failure:failure];
}

- (MXHTTPOperation*)directoryVisibility:(void (^)(MXRoomDirectoryVisibility directoryVisibility))success
                                failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient directoryVisibilityOfRoom:self.roomId success:success failure:failure];
}

- (MXHTTPOperation*)join:(void (^)())success
                 failure:(void (^)(NSError *error))failure
{
    return [mxSession joinRoom:self.roomId success:^(MXRoom *room) {
        success();
    } failure:failure];
}

- (MXHTTPOperation*)leave:(void (^)())success
                  failure:(void (^)(NSError *error))failure
{
    return [mxSession leaveRoom:self.roomId success:success failure:failure];
}

- (MXHTTPOperation*)inviteUser:(NSString*)userId
                       success:(void (^)())success
                       failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient inviteUser:userId toRoom:self.roomId success:success failure:failure];
}

- (MXHTTPOperation*)inviteUserByEmail:(NSString*)email
                              success:(void (^)())success
                              failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient inviteUserByEmail:email toRoom:self.roomId success:success failure:failure];
}

- (MXHTTPOperation*)kickUser:(NSString*)userId
                      reason:(NSString*)reason
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient kickUser:userId fromRoom:self.roomId reason:reason success:success failure:failure];
}

- (MXHTTPOperation*)banUser:(NSString*)userId
                     reason:(NSString*)reason
                    success:(void (^)())success
                    failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient banUser:userId inRoom:self.roomId reason:reason success:success failure:failure];
}

- (MXHTTPOperation*)unbanUser:(NSString*)userId
                      success:(void (^)())success
                      failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient unbanUser:userId inRoom:self.roomId success:success failure:failure];
}

- (MXHTTPOperation*)setPowerLevelOfUserWithUserID:(NSString *)userId powerLevel:(NSInteger)powerLevel
                                          success:(void (^)())success
                                          failure:(void (^)(NSError *))failure
{
    // To set this new value, we have to take the current powerLevels content,
    // Update it with expected values and send it to the home server.
    NSMutableDictionary *newPowerLevelsEventContent = [NSMutableDictionary dictionaryWithDictionary:self.state.powerLevels.JSONDictionary];

    NSMutableDictionary *newPowerLevelsEventContentUsers = [NSMutableDictionary dictionaryWithDictionary:newPowerLevelsEventContent[@"users"]];
    newPowerLevelsEventContentUsers[userId] = [NSNumber numberWithInteger:powerLevel];

    newPowerLevelsEventContent[@"users"] = newPowerLevelsEventContentUsers;

    // Make the request to the HS
    return [self sendStateEventOfType:kMXEventTypeStringRoomPowerLevels content:newPowerLevelsEventContent success:^(NSString *eventId) {
        success();
    } failure:failure];
}

- (MXHTTPOperation*)sendTypingNotification:(BOOL)typing
                                   timeout:(NSUInteger)timeout
                                   success:(void (^)())success
                                   failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient sendTypingNotificationInRoom:self.roomId typing:typing timeout:timeout success:success failure:failure];
}

- (MXHTTPOperation*)redactEvent:(NSString*)eventId
                         reason:(NSString*)reason
                        success:(void (^)())success
                        failure:(void (^)(NSError *error))failure
{
    return [mxSession.matrixRestClient redactEvent:eventId inRoom:self.roomId reason:reason success:success failure:failure];
}

- (MXHTTPOperation *)reportEvent:(NSString *)eventId
                           score:(NSInteger)score
                          reason:(NSString *)reason
                         success:(void (^)())success
                         failure:(void (^)(NSError *))failure
{
    return [mxSession.matrixRestClient reportEvent:eventId inRoom:self.roomId score:score reason:reason success:success failure:failure];
}


#pragma mark - Events timeline
- (MXEventTimeline*)timelineOnEvent:(NSString*)eventId;
{
    return [[MXEventTimeline alloc] initWithRoom:self andInitialEventId:eventId];
}


#pragma mark - Fake event objects creation
- (MXEvent*)fakeRoomMessageEventWithEventId:(NSString*)eventId andContent:(NSDictionary*)content
{
    if (!eventId)
    {
        eventId = [NSString stringWithFormat:@"%@%@", kMXEventLocalEventIdPrefix, [[NSProcessInfo processInfo] globallyUniqueString]];
    }
    
    MXEvent *event = [[MXEvent alloc] init];
    event.roomId = _roomId;
    event.eventId = eventId;
    event.wireType = kMXEventTypeStringRoomMessage;
    event.originServerTs = (uint64_t) ([[NSDate date] timeIntervalSince1970] * 1000);
    event.sender = mxSession.myUser.userId;
    event.wireContent = content;
    
    return event;
}


#pragma mark - Outgoing events management
- (void)storeOutgoingMessage:(MXEvent*)outgoingMessage
{
    if ([mxSession.store respondsToSelector:@selector(storeOutgoingMessageForRoom:outgoingMessage:)]
        && [mxSession.store respondsToSelector:@selector(commit)])
    {
        [mxSession.store storeOutgoingMessageForRoom:self.roomId outgoingMessage:outgoingMessage];
        [mxSession.store commit];
    }
}

- (void)removeAllOutgoingMessages
{
    if ([mxSession.store respondsToSelector:@selector(removeAllOutgoingMessagesFromRoom:)]
        && [mxSession.store respondsToSelector:@selector(commit)])
    {
        [mxSession.store removeAllOutgoingMessagesFromRoom:self.roomId];
        [mxSession.store commit];
    }
}

- (void)removeOutgoingMessage:(NSString*)outgoingMessageEventId
{
    if ([mxSession.store respondsToSelector:@selector(removeOutgoingMessageFromRoom:outgoingMessage:)]
        && [mxSession.store respondsToSelector:@selector(commit)])
    {
        [mxSession.store removeOutgoingMessageFromRoom:self.roomId outgoingMessage:outgoingMessageEventId];
        [mxSession.store commit];
    }
}

- (void)updateOutgoingMessage:(NSString *)outgoingMessageEventId withOutgoingMessage:(MXEvent *)outgoingMessage
{
    // Do the update by removing the existing one and create a new one
    // Thus, `outgoingMessage` will go at the end of the outgoing messages list
    [self removeOutgoingMessage:outgoingMessageEventId];
    [self storeOutgoingMessage:outgoingMessage];
}

- (NSArray<MXEvent*>*)outgoingMessages
{
    if ([mxSession.store respondsToSelector:@selector(outgoingMessagesInRoom:)])
    {
        NSArray<MXEvent*> *outgoingMessages = [mxSession.store outgoingMessagesInRoom:self.roomId];
        
        for (MXEvent *event in outgoingMessages)
        {
            // Decrypt event if necessary
            if (event.eventType == MXEventTypeRoomEncrypted)
            {
                if (![self.mxSession decryptEvent:event inTimeline:nil])
                {
                    NSLog(@"[MXRoom] outgoingMessages: Warning: Unable to decrypt outgoing event: %@", event.decryptionError);
                }
            }
        }
        
        return outgoingMessages;
    }
    else
    {
        return nil;
    }
}

- (void)refreshOutgoingMessages
{
    // Update the stored outgoing messages, by removing the sent messages and tagging as failed the others.
    NSArray<MXEvent*>* outgoingMessages = self.outgoingMessages;
    
    if (outgoingMessages.count && [mxSession.store respondsToSelector:@selector(commit)])
    {
        for (NSInteger index = 0; index < outgoingMessages.count;)
        {
            MXEvent *outgoingMessage = [outgoingMessages objectAtIndex:index];
            
            // Remove successfully sent messages
            if (outgoingMessage.isLocalEvent == NO)
            {
                if ([mxSession.store respondsToSelector:@selector(removeOutgoingMessageFromRoom:outgoingMessage:)])
                {
                    [mxSession.store removeOutgoingMessageFromRoom:_roomId outgoingMessage:outgoingMessage.eventId];
                    continue;
                }
            }
            else
            {
                // Here the message sending has failed
                outgoingMessage.sentState = MXEventSentStateFailed;
                
                // Erase the timestamp
                outgoingMessage.originServerTs = kMXUndefinedTimestamp;
            }
            
            index++;
        }
        
        [mxSession.store commit];
    }
}

#pragma mark - Local echo handling

- (MXEvent*)addLocalEchoForMessageContent:(NSDictionary*)msgContent withState:(MXEventSentState)eventState
{
    // Create a room message event.
    MXEvent *localEcho = [self fakeRoomMessageEventWithEventId:nil andContent:msgContent];
    localEcho.sentState = eventState;
    
    // Register the echo as pending for its future deletion
    [self storeOutgoingMessage:localEcho];
    
    return localEcho;
}

- (MXEvent*)pendingLocalEchoRelatedToEvent:(MXEvent*)event
{
    // Note: event is supposed here to be an outgoing event received from the server sync.
    
    NSString *msgtype = event.content[@"msgtype"];
    
    // We look first for a pending event with the same event id (This happens when server response is received before server sync).
    MXEvent *localEcho = nil;
    NSArray<MXEvent*>* pendingLocalEchoes = self.outgoingMessages;
    for (NSInteger index = 0; index < pendingLocalEchoes.count; index++)
    {
        localEcho = [pendingLocalEchoes objectAtIndex:index];
        if ([localEcho.eventId isEqualToString:event.eventId])
        {
            break;
        }
        localEcho = nil;
    }
    
    // If none, we return the pending event (if any) whose content matches with received event content.
    if (!localEcho)
    {
        for (NSInteger index = 0; index < pendingLocalEchoes.count; index++)
        {
            localEcho = [pendingLocalEchoes objectAtIndex:index];
            NSString *pendingEventType = localEcho.content[@"msgtype"];
            
            if ([msgtype isEqualToString:pendingEventType])
            {
                if ([msgtype isEqualToString:kMXMessageTypeText] || [msgtype isEqualToString:kMXMessageTypeEmote])
                {
                    // Compare content body
                    if ([event.content[@"body"] isEqualToString:localEcho.content[@"body"]])
                    {
                        break;
                    }
                }
                else if ([msgtype isEqualToString:kMXMessageTypeLocation])
                {
                    // Compare geo uri
                    if ([event.content[@"geo_uri"] isEqualToString:localEcho.content[@"geo_uri"]])
                    {
                        break;
                    }
                }
                else
                {
                    // Here the type is kMXMessageTypeImage, kMXMessageTypeAudio, kMXMessageTypeVideo or kMXMessageTypeFile
                    if (event.content[@"file"])
                    {
                        // This is an encrypted attachment
                        if (localEcho.content[@"file"] && [event.content[@"file"][@"url"] isEqualToString:localEcho.content[@"file"][@"url"]])
                        {
                            break;
                        }
                    }
                    else if ([event.content[@"url"] isEqualToString:localEcho.content[@"url"]])
                    {
                        break;
                    }
                }
            }
            localEcho = nil;
        }
    }
    
    return localEcho;
}

- (void)removePendingLocalEcho:(NSString*)localEchoEventId
{
    [self removeOutgoingMessage:localEchoEventId];
}


#pragma mark - Room tags operations
- (MXHTTPOperation*)addTag:(NSString*)tag
                 withOrder:(NSString*)order
                   success:(void (^)())success
                   failure:(void (^)(NSError *error))failure
{
    // _accountData.tags will be updated by the live streams
    return [mxSession.matrixRestClient addTag:tag withOrder:order toRoom:self.roomId success:success failure:failure];
}

- (MXHTTPOperation*)removeTag:(NSString*)tag
                      success:(void (^)())success
                      failure:(void (^)(NSError *error))failure
{
    // _accountData.tags will be updated by the live streams
    return [mxSession.matrixRestClient removeTag:tag fromRoom:self.roomId success:success failure:failure];
}

- (MXHTTPOperation*)replaceTag:(NSString*)oldTag
                         byTag:(NSString*)newTag
                     withOrder:(NSString*)newTagOrder
                       success:(void (^)())success
                       failure:(void (^)(NSError *error))failure
{
    MXHTTPOperation *operation;
    
    // remove tag
    if (oldTag && !newTag)
    {
        operation = [self removeTag:oldTag success:success failure:failure];
    }
    // define a tag or define a new order
    else if ((!oldTag && newTag) || [oldTag isEqualToString:newTag])
    {
        operation = [self addTag:newTag withOrder:newTagOrder success:success failure:failure];
    }
    else
    {
        // the tag is not the same
        // weird, but the tag must be removed and defined again
        // so combine remove and add tag operations
        operation = [self removeTag:oldTag success:^{
            
            MXHTTPOperation *addTagHttpOperation = [self addTag:newTag withOrder:newTagOrder success:success failure:failure];
            
            // Transfer the new AFHTTPRequestOperation to the returned MXHTTPOperation
            // So that user has hand on it
            operation.operation = addTagHttpOperation.operation;
            
        } failure:failure];
    }
    
    return operation;
}


#pragma mark - Voice over IP
- (void)placeCallWithVideo:(BOOL)video
                   success:(void (^)(MXCall *call))success
                   failure:(void (^)(NSError *error))failure
{
    if (mxSession.callManager)
    {
        [mxSession.callManager placeCallInRoom:self.roomId withVideo:video success:success failure:failure];
    }
    else if (failure)
    {
        failure(nil);
    }
}

#pragma mark - Read receipts management

- (BOOL)handleReceiptEvent:(MXEvent *)event direction:(MXTimelineDirection)direction
{
    BOOL managedEvents = false;
    
    NSArray* eventIds = [event.content allKeys];
    
    for(NSString* eventId in eventIds)
    {
        NSDictionary* eventDict = [event.content objectForKey:eventId];
        NSDictionary* readDict = [eventDict objectForKey:kMXEventTypeStringRead];
        
        if (readDict)
        {
            NSArray* userIds = [readDict allKeys];
            
            for(NSString* userId in userIds)
            {
                NSDictionary* params = [readDict objectForKey:userId];
                
                if ([params valueForKey:@"ts"])
                {
                    MXReceiptData* data = [[MXReceiptData alloc] init];
                    data.userId = userId;
                    data.eventId = eventId;
                    data.ts = ((NSNumber*)[params objectForKey:@"ts"]).longLongValue;
                    
                    managedEvents |= [mxSession.store storeReceipt:data inRoom:self.roomId];
                }
            }
        }
    }
    
    // warn only if the receipts are not duplicated ones.
    if (managedEvents)
    {
        // Notify listeners
        [_liveTimeline notifyListeners:event direction:direction];
    }
    
    return managedEvents;
}

- (BOOL)acknowledgeEvent:(MXEvent*)event
{
    // Sanity check
    if (!event.eventId)
    {
        return NO;
    }
    
    // Retrieve the current position
    NSString *currentEventId;
    NSString *myUserId = mxSession.myUser.userId;
    MXReceiptData* currentData = [mxSession.store getReceiptInRoom:self.roomId forUserId:myUserId];
    if (currentData)
    {
        currentEventId = currentData.eventId;
    }
    
    // Check whether the provided event is acknowledgeable
    BOOL isAcknowledgeable = ([mxSession.acknowledgableEventTypes indexOfObject:event.type] != NSNotFound);
    
    // Check whether the event is posterior to the current position (if any).
    // Look for an acknowledgeable event if the event type is not acknowledgeable.
    if (currentEventId || !isAcknowledgeable)
    {
        @autoreleasepool
        {
            // Enumerate all the acknowledgeable events of the room
            id<MXEventsEnumerator> messagesEnumerator = [mxSession.store messagesEnumeratorForRoom:self.roomId withTypeIn:mxSession.acknowledgableEventTypes ignoreMemberProfileChanges:NO];

            MXEvent *nextEvent;
            while ((nextEvent = messagesEnumerator.nextEvent))
            {
                // Look for the first acknowledgeable event prior the event timestamp
                if (nextEvent.originServerTs <= event.originServerTs && nextEvent.eventId)
                {
                    if ([nextEvent.eventId isEqualToString:event.eventId] == NO)
                    {
                        event = nextEvent;
                    }

                    // Here we find the right event to acknowledge, and it is posterior to the current position (if any).
                    break;
                }

                // Check whether the current acknowledged event is posterior to the provided event.
                if (currentEventId && [nextEvent.eventId isEqualToString:currentEventId])
                {
                    // No change is required
                    return NO;
                }
            }
        }
    }
    
    // Sanity check: Do not send read receipt on a fake event id
    if ([event.eventId hasPrefix:kMXRoomInviteStateEventIdPrefix] == NO)
    {
        // Update the oneself receipts
        MXReceiptData *data = [[MXReceiptData alloc] init];
        
        data.userId = myUserId;
        data.eventId = event.eventId;
        data.ts = (uint64_t) ([[NSDate date] timeIntervalSince1970] * 1000);
        
        if ([mxSession.store storeReceipt:data inRoom:self.roomId])
        {
            if ([mxSession.store respondsToSelector:@selector(commit)])
            {
                [mxSession.store commit];
            }
            
            [mxSession.matrixRestClient sendReadReceipts:self.roomId eventId:event.eventId success:^(NSString *eventId) {
                
            } failure:^(NSError *error) {
                
            }];
            
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)acknowledgeLatestEvent:(BOOL)sendReceipt;
{
    @autoreleasepool
    {
        id<MXEventsEnumerator> messagesEnumerator = [mxSession.store messagesEnumeratorForRoom:self.roomId withTypeIn:mxSession.acknowledgableEventTypes ignoreMemberProfileChanges:NO];

        // Acknowledge the lastest valid event
        MXEvent *event;
        while ((event = messagesEnumerator.nextEvent))
        {
            // Sanity check on event id: Do not send read receipt on event without id
            if (event.eventId && ([event.eventId hasPrefix:kMXRoomInviteStateEventIdPrefix] == NO))
            {
                // Check whether this is the current position of the user
                NSString* myUserId = mxSession.myUser.userId;
                MXReceiptData* currentData = [mxSession.store getReceiptInRoom:self.roomId forUserId:myUserId];

                if (currentData && [currentData.eventId isEqualToString:event.eventId])
                {
                    // No change is required
                    return NO;
                }

                // Update the oneself receipts
                MXReceiptData *data = [[MXReceiptData alloc] init];

                data.userId = myUserId;
                data.eventId = event.eventId;
                data.ts = (uint64_t) ([[NSDate date] timeIntervalSince1970] * 1000);

                if ([mxSession.store storeReceipt:data inRoom:self.roomId])
                {
                    if ([mxSession.store respondsToSelector:@selector(commit)])
                    {
                        [mxSession.store commit];
                    }

                    if (sendReceipt)
                    {
                        [mxSession.matrixRestClient sendReadReceipts:self.roomId eventId:event.eventId success:^(NSString *eventId) {
                            
                        } failure:^(NSError *error) {
                            
                        }];
                    }
                    
                    return YES;
                }
            }
        }
    }

    return NO;
}

- (NSUInteger)localUnreadEventCount
{
    // Check for unread events in store
    return [mxSession.store localUnreadEventCount:self.roomId withTypeIn:mxSession.unreadEventTypes];
}

- (NSUInteger)notificationCount
{
    return [mxSession.store notificationCountOfRoom:self.roomId];
}

- (NSUInteger)highlightCount
{
    return [mxSession.store highlightCountOfRoom:self.roomId];
}

- (BOOL)isDirect
{
    // Check whether this room is tagged as direct for one of the room members.
    return ([self getDirectUserId] != nil);
}

- (BOOL)looksLikeDirect
{
    BOOL kicked = NO;
    if (self.state.membership == MXMembershipLeave)
    {
        MXRoomMember *member = [self.state memberWithUserId:mxSession.myUser.userId];
        kicked = ![member.originalEvent.sender isEqualToString:mxSession.myUser.userId];
    }
    
    if (self.state.membership == MXMembershipJoin || self.state.membership == MXMembershipBan || kicked)
    {
        // Consider as direct chats the 1:1 chats.
        // Contrary to the web client we allow the tagged rooms (favorite/low priority...) to become direct.
        if (self.state.members.count == 2)
        {
            return YES;
        }
    }
    return NO;
}

- (MXHTTPOperation*)setIsDirect:(BOOL)isDirect
                     withUserId:(NSString*)userId
                        success:(void (^)())success
                        failure:(void (^)(NSError *error))failure
{
    NSString *currentDirectUserId = [self getDirectUserId];
    
    if (isDirect == NO)
    {
        if (currentDirectUserId)
        {
            NSMutableArray *roomLists = [NSMutableArray arrayWithArray:mxSession.directRooms[currentDirectUserId]];
            
            [roomLists removeObject:self.roomId];
            
            if (roomLists.count)
            {
                [mxSession.directRooms setObject:roomLists forKey:currentDirectUserId];
            }
            else
            {
                [mxSession.directRooms removeObjectForKey:currentDirectUserId];
            }
            
            // Note: mxSession will post the 'kMXSessionDirectRoomsDidChangeNotification' notification on account data update.
            return [mxSession uploadDirectRooms:success failure:failure];
        }
    }
    else if (!currentDirectUserId || (userId && ![userId isEqualToString:currentDirectUserId]))
    {
        // Here the room is not direct yet, or it is direct with the wrong user
        NSString *directUserId = userId;
        
        if (!directUserId)
        {
            // By default mark as direct this room for the oldest joined member.
            NSArray *members = self.state.joinedMembers;
            MXRoomMember *oldestJoinedMember;
            
            for (MXRoomMember *member in members)
            {
                if (![member.userId isEqualToString:mxSession.myUser.userId])
                {
                    if (!oldestJoinedMember)
                    {
                        oldestJoinedMember = member;
                    }
                    else if (member.originalEvent.originServerTs < oldestJoinedMember.originalEvent.originServerTs)
                    {
                        oldestJoinedMember = member;
                    }
                }
            }
            
            directUserId = oldestJoinedMember.userId;
            if (!directUserId)
            {
                // Consider the first invited member if none has joined
                members = [self.state membersWithMembership:MXMembershipInvite];
                
                MXRoomMember *oldestInvitedMember;
                for (MXRoomMember *member in members)
                {
                    if (![member.userId isEqualToString:mxSession.myUser.userId])
                    {
                        if (!oldestInvitedMember)
                        {
                            oldestInvitedMember = member;
                        }
                        else if (member.originalEvent.originServerTs < oldestInvitedMember.originalEvent.originServerTs)
                        {
                            oldestInvitedMember = member;
                        }
                    }
                }
                
                directUserId = oldestInvitedMember.userId;
            }
            
            if (!directUserId)
            {
                // Use the current user by default
                directUserId = mxSession.myUser.userId;
            }
        }
        
        // Add the room id in the direct chats list for this user
        NSMutableArray *roomLists = (mxSession.directRooms[directUserId] ? [NSMutableArray arrayWithArray:mxSession.directRooms[directUserId]] : [NSMutableArray array]);
        [roomLists addObject:self.roomId];
        [mxSession.directRooms setObject:roomLists forKey:directUserId];
        
        // Remove the room id for the current direct user if any
        if (currentDirectUserId)
        {
            roomLists = [NSMutableArray arrayWithArray:mxSession.directRooms[currentDirectUserId]];
            [roomLists removeObject:self.roomId];
            if (roomLists.count)
            {
                [mxSession.directRooms setObject:roomLists forKey:currentDirectUserId];
            }
            else
            {
                [mxSession.directRooms removeObjectForKey:currentDirectUserId];
            }
        }
        
        // Note: mxSession will post the 'kMXSessionDirectRoomsDidChangeNotification' notification on account data update.
        return [mxSession uploadDirectRooms:success failure:failure];
    }
    
    // Here the room has already the right value for the direct tag
    if (success)
    {
        success();
    }
    
    return nil;
}

- (NSString*)getDirectUserId
{
    // Return the user identifier for who this room is tagged as direct if any.
    NSString *directUserId;
    
    // Enumerate all the user identifiers for which a direct chat is defined.
    NSArray *userIdWithDirectRoom = mxSession.directRooms.allKeys;
    
    for (NSString *userId in userIdWithDirectRoom)
    {
        // Check whether this user is a member of this room.
        if ([self.state memberWithUserId:userId])
        {
            // Check whether this room is tagged as direct for this user
            if ([mxSession.directRooms[userId] indexOfObject:self.roomId] != NSNotFound)
            {
                // Matched!
                directUserId = userId;
                break;
            }
        }
    }
    
    return directUserId;
}

- (NSArray*)getEventReceipts:(NSString*)eventId sorted:(BOOL)sort
{
    NSArray *receipts = [mxSession.store getEventReceipts:self.roomId eventId:eventId sorted:sort];
    
    // if some receipts are found
    if (receipts)
    {
        NSString* myUserId = mxSession.myUser.userId;
        NSMutableArray* res = [[NSMutableArray alloc] init];
        
        // Remove the oneself receipts
        for (MXReceiptData* data in receipts)
        {
            if (![data.userId isEqualToString:myUserId])
            {
                [res addObject:data];
            }
        }
        
        if (res.count > 0)
        {
            receipts = res;
        }
        else
        {
            receipts = nil;
        }
    }
    
    return receipts;
}


#pragma mark - Crypto

- (MXHTTPOperation *)enableEncryptionWithAlgorithm:(NSString *)algorithm
                                           success:(void (^)())success failure:(void (^)(NSError *))failure
{
    MXHTTPOperation *operation;

    if (mxSession.crypto)
    {
        // Send the information to the homeserver
        operation = [self sendStateEventOfType:kMXEventTypeStringRoomEncryption
                                  content:@{
                                            @"algorithm": algorithm
                                            }
                                  success:nil
                                  failure:failure];

        // Wait for the event coming back from the hs
        id eventBackListener;
        eventBackListener = [_liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomEncryption] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

            [_liveTimeline removeListener:eventBackListener];

            // Dispatch to let time to MXCrypto to digest the m.room.encryption event
            dispatch_async(dispatch_get_main_queue(), ^{
                success();
            });
        }];
    }
    else
    {
        failure([NSError errorWithDomain:MXDecryptingErrorDomain
                                    code:MXDecryptingErrorEncryptionNotEnabledCode
                                userInfo:@{
                                           NSLocalizedDescriptionKey: MXDecryptingErrorEncryptionNotEnabledReason
                                           }]);
    }

    return operation;
}

#pragma mark - Utils
- (NSComparisonResult)compareOriginServerTs:(MXRoom *)otherRoom
{
    return [[otherRoom lastMessageWithTypeIn:nil] compareOriginServerTs:[self lastMessageWithTypeIn:nil]];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MXRoom: %p> %@: %@ - %@", self, self.roomId, self.state.name, self.state.topic];
}

@end

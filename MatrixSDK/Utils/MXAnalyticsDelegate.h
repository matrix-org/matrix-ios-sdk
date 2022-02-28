/*
 Copyright 2017 Avery Pierce
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

#import "MXCallHangupEventContent.h"
#import "MXTaskProfile.h"

NS_ASSUME_NONNULL_BEGIN

/**
 The MXAnalyticsDelegate protocol is used to capture analytics events.
 If you want to capture these analytics events for your own metrics, you
 should create a class that implements this protocol and set it to the
 MXSDKOptions singleton's analyticsDelegate property.
 
 @code
 MyAnalyticsDelegate *delegate = [[MyAnalyticsDelegate alloc] init];
 [MXSDKOptions shared].analyticsDelegate = delegate;
 @endcode
 */
@protocol MXAnalyticsDelegate <NSObject>

/**
 Report the duration of a task.
 
 An example is the time to load data from the local store at startup.
 
 @param milliseconds the duration in milliseconds.
 @param name the name of the task.
 @param units the number of items the were completed during the task
 */
- (void)trackDuration:(NSInteger)milliseconds name:(MXTaskProfileName)name units:(NSUInteger)units;

/**
 Report that a call has started.
 
 @param isVideo Whether the call is a video call
 @param numberOfParticipants The number of participants in the call
 @param isIncoming Whether the call is an incoming call (NO if placed by the user).
 */
- (void)trackCallStartedWithVideo:(BOOL)isVideo numberOfParticipants:(NSInteger)numberOfParticipants incoming:(BOOL)isIncoming;

/**
 Report that a call has ended.
 
 @param duration The duration of the call in milliseconds
 @param isVideo Whether the call is a video call
 @param numberOfParticipants The number of participants in the call
 @param isIncoming Whether the call is an incoming call (NO if placed by the user).
 */
- (void)trackCallEndedWithDuration:(NSInteger)duration video:(BOOL)isVideo numberOfParticipants:(NSInteger)numberOfParticipants incoming:(BOOL)isIncoming;

/**
 Report that a call encountered an error.
 
 @param reason The call hangup reason.
 @param isVideo Whether the call is a video call
 @param numberOfParticipants The number of participants in the call
 @param isIncoming Whether the call is an incoming call (NO if placed by the user).
 */
- (void)trackCallErrorWithReason:(MXCallHangupReason)reason video:(BOOL)isVideo numberOfParticipants:(NSInteger)numberOfParticipants incoming:(BOOL)isIncoming;

/**
 Report that a room was created.
 
 @param isDM Whether the room is direct or not.
 */
- (void)trackCreatedRoomAsDM:(BOOL)isDM;

/**
 Report that a room was joined.
 
 @param isDM Whether the room is direct or not.
 @param memberCount The number of members in the room.
 */
- (void)trackJoinedRoomAsDM:(BOOL)isDM memberCount:(NSUInteger)memberCount;

/**
 Report whether the user granted or rejected access to their contacts.
 
 @param granted YES if access was granted, NO if it was rejected.
 */
- (void)trackContactsAccessGranted:(BOOL)granted;

#pragma mark - Threads

/**
 Report that an event composed.

 @param inThread flag indicating the event was senf in a thread
 @param isEditing flag indicating the event was an edit
 @param isReply flag indicating the event was a reply
 @param startsThread flag indicating the event starts a thread
 */
- (void)trackEventComposedInThread:(BOOL)inThread
                         isEditing:(BOOL)isEditing
                           isReply:(BOOL)isReply
                      startsThread:(BOOL)startsThread;

@end

NS_ASSUME_NONNULL_END


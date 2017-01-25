/*
 Copyright 2017 OpenMarket Ltd

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

#import "MXJSONModels.h"

@class MXSession, MXRoom, MXRoomState, MXEvent;


/**
 Posted when a room summary has changed.
 */
FOUNDATION_EXPORT NSString *const kMXRoomSummaryDidChangeNotification;


/**
 `MXRoomSummary` exposes information about a room.

 The data is thus cached to avoid to recompute it everytime from the room state.
 */
@interface MXRoomSummary : NSObject <NSCoding>

/**
 The Matrix id of the room.
 */
@property (nonatomic, readonly) NSString *roomId;

/**
 The related matrix session.
 */
@property (nonatomic, readonly) MXSession *mxSession;

/**
 Shortcut to the corresponding room.
 */
@property (nonatomic, readonly) MXRoom *room;

/**
 Create a `MXRoom` instance.

 @param roomId the id of the room.
 @param mxSession the session to use.
 @return the new instance.
 */
- (instancetype)initWithRoomId:(NSString*)roomId andMatrixSession:(MXSession*)mxSession;

/**
 Set the Matrix session.

 Must be used for MXRoomSummary instance loaded from the store.

 @param mxSession the session to use.
 */
- (void)setMatrixSession:(MXSession*)mxSession;

/**
 Reset and recompute summary data.
 */
- (void)reset;

/**
 Save room summary data.
 
 This method must be called when data is modified outside the `MXRoomSummaryUpdating` callbacks.
 It will generate a `kMXRoomSummaryDidChangeNotification`.
 */
- (void)save;


#pragma mark - Data related to room state

/**
 The avatar url of the room.
 */
@property (nonatomic) NSString *avatar;

/**
 The computed display name of the room.
 */
@property (nonatomic) NSString *displayname;

/**
 The topic of the room.
 */
@property (nonatomic) NSString *topic;

/**
 The number of unread messages that match the push notification rules.
 It is based on the notificationCount field in /sync response.
 (kMXRoomDidUpdateUnreadNotification is posted when this property is updated)
 */
//@property (nonatomic) NSUInteger notificationCount;

/**
 The number of highlighted unread messages (subset of notifications).
 It is based on the notificationCount field in /sync response.
 (kMXRoomDidUpdateUnreadNotification is posted when this property is updated)
 */
//@property (nonatomic) NSUInteger highlightCount;

// @TODO: Add:

/*
 isEncrypted;
 isDirect;
 looksLikeDirect;
 additional NSDictionary or id<NSCoding> ?
 */

// @TODO (from Android)
//// defines the late
//private String mLatestReadEventId;
//
//private int mUnreadEventsCount;

//private boolean mIsHighlighted = false;

/**
 Placeholder to store more information in the room summary
 */
@property (nonatomic) NSMutableDictionary<NSString*, id<NSCoding>> *others;


#pragma mark - Data related to the last event

/**
 The last event id.
 */
@property (nonatomic) NSString *lastEventId;

/**
 String representation of this last event.
 */
@property (nonatomic) NSString *lastEventString;
@property (nonatomic) NSAttributedString *lastEventAttribytedString;

/**
 The shortcut to the last event.
 */
@property (nonatomic, readonly) MXEvent *lastEvent;


#pragma mark - Server sync

/**
 Update room summary data according to the provided sync response.

 @param roomSync information to sync the room with the home server data.
 */
- (void)handleJoinedRoomSync:(MXRoomSync*)roomSync;

/**
 Update the invited room state according to the provided data.

 @param invitedRoom information to update the room state.
 */
- (void)handleInvitedRoomSync:(MXInvitedRoomSync*)invitedRoomSync;


#pragma mark - Single update

/**
 Update room summary with this event.

 @param event an candidate for the last event.
 */
- (void)handleEvent:(MXEvent*)event;

@end


/**
 The `MXRoomSummaryUpdating` allows delegation of the update of room summaries.
 */
@protocol MXRoomSummaryUpdating

/**
 Called to update the last event of the room summary.

 @param session the session the room belongs to.
 @param summary the room summary.
 @param event the candidate event for the room last event.
 @return YES if the delegate accepted the event as last event.
         Returning NO can lead to a new call of this method with another candidate event.
 */
- (BOOL)session:(MXSession*)session updateRoomSummary:(MXRoomSummary*)summary withLastEvent:(MXEvent*)event oldState:(MXRoomState*)oldState;

/**
 Called to update the room summary on a received state event.

 @param session the session the room belongs to.
 @param summary the room summary.
 @param event a state event that may change the room summary.
 @return YES if the room summary has changed.
 */
- (BOOL)session:(MXSession*)session updateRoomSummary:(MXRoomSummary*)summary withStateEvent:(MXEvent*)event;

@end



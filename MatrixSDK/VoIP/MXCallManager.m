/*
 Copyright 2015 OpenMarket Ltd

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

#import "MXCallManager.h"

#import "MXSession.h"

#pragma mark - Constants definitions
NSString *const kMXCallManagerNewCall = @"kMXCallManagerNewCall";

// Use Google STUN server as fallback
NSString *const kMXCallManagerFallbackSTUNServer = @"stun:stun.l.google.com:19302";

@interface MXCallManager ()
{
    /**
     Calls being handled.
     */
    NSMutableArray *calls;

    /**
     Listener to Matrix call-related events.
     */
    id callEventsListener;

    /**
     Timer to periodically refresh the TURN server config.
     */
    NSTimer *refreshTURNServerTimer;
}
@end


@implementation MXCallManager

- (instancetype)initWithMatrixSession:(MXSession *)mxSession andCallStack:(id<MXCallStack>)callstack
{
    self = [super init];
    if (self)
    {
        _mxSession = mxSession;
        calls = [NSMutableArray array];
        _fallbackSTUNServer = kMXCallManagerFallbackSTUNServer;
        _inviteLifetime = 30000;

        _callStack = callstack;

        // Listen to call events
        callEventsListener = [mxSession listenToEventsOfTypes:@[
                                                                kMXEventTypeStringCallInvite,
                                                                kMXEventTypeStringCallCandidates,
                                                                kMXEventTypeStringCallAnswer,
                                                                kMXEventTypeStringCallHangup
                                                                ]
                                                      onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

            if (MXTimelineDirectionForwards == direction)
            {
                switch (event.eventType)
                {
                    case MXEventTypeCallInvite:
                        [self handleCallInvite:event];
                        break;

                    case MXEventTypeCallAnswer:
                        [self handleCallAnswer:event];
                        break;

                    case MXEventTypeCallHangup:
                        [self handleCallHangup:event];
                        break;

                    case MXEventTypeCallCandidates:
                        [self handleCallCandidates:event];
                        break;
                    default:
                        break;
                }
            }
        }];

        [self refreshTURNServer];
    }
    return self;
}

- (void)close
{
    [_mxSession removeListener:callEventsListener];
    callEventsListener = nil;

    // Hang up all calls
    for (MXCall *call in calls)
    {
        [call hangup];
    }
    [calls removeAllObjects];
    calls = nil;

    // Do not refresh TURN servers config anymore
    [refreshTURNServerTimer invalidate];
    refreshTURNServerTimer = nil;
}

- (MXCall *)callWithCallId:(NSString *)callId
{
    MXCall *theCall;
    for (MXCall *call in calls)
    {
        if ([call.callId isEqualToString:callId])
        {
            theCall = call;
            break;
        }
    }
    return theCall;
}

- (MXCall *)callInRoom:(NSString *)roomId
{
    MXCall *theCall;
    for (MXCall *call in calls)
    {
        if ([call.callSignalingRoom.state.roomId isEqualToString:roomId])
        {
            theCall = call;
            break;
        }
    }
    return theCall;
}

- (void)placeCallInRoom:(NSString*)roomId withVideo:(BOOL)video
                success:(void (^)(MXCall *call))success
                failure:(void (^)(NSError *error))failure
{
    MXRoom *room = [_mxSession roomWithRoomId:roomId];

    if (room && 1 < room.state.joinedMembers.count)
    {
        if (2 == room.state.joinedMembers.count)
        {
            // Do a peer to peer, one to one call
            MXCall *call = [[MXCall alloc] initWithRoomId:roomId andCallManager:self];
            if (call)
            {
                [calls addObject:call];

                [call callWithVideo:video];

                // Broadcast the new outgoing call
                [[NSNotificationCenter defaultCenter] postNotificationName:kMXCallManagerNewCall object:call userInfo:nil];
            }

            if (success)
            {
                success(call);
            }
        }
        else
        {
            // Use the conference server bot to manage the conf call
            // There are 2 steps:
            //    - invite the conference user (the bot) into the room
            //    - set up a separated private room with the conference user to manage
            //      the conf call in 'room'
            [self inviteConferenceUserToRoom:room success:^{

                [self conferenceUserRoomForRoom:roomId success:^(MXRoom *conferenceUserRoom) {

                    // The call can now be created
                    MXCall *call = [[MXCall alloc] initWithRoomId:roomId callSignalingRoomId:conferenceUserRoom.roomId andCallManager:self];
                    if (call)
                    {
                        [calls addObject:call];

                        [call callWithVideo:video];

                        // Broadcast the new outgoing call
                        [[NSNotificationCenter defaultCenter] postNotificationName:kMXCallManagerNewCall object:call userInfo:nil];
                    }

                    if (success)
                    {
                        success(call);
                    }
                } failure:failure];

            } failure:failure];
        }
    }
    else
    {
        NSLog(@"[MXCallManager] placeCallInRoom: ERROR: Cannot place call in %@. Members count: %tu", roomId, room.state.joinedMembers.count);

        if (failure)
        {
            // @TODO: Provide an error
            failure(nil);
        }
    }
}

- (void)removeCall:(MXCall *)call
{
    [calls removeObject:call];
}


#pragma mark - Private methods
- (void)refreshTURNServer
{
    [_mxSession.matrixRestClient turnServer:^(MXTurnServerResponse *turnServerResponse) {

        // Check this MXCallManager is still alive
        if (calls)
        {
            NSLog(@"[MXCallManager] refreshTURNServer: TTL:%tu URIs: %@", turnServerResponse.ttl, turnServerResponse.uris);

            if (turnServerResponse.uris)
            {
                _turnServers = turnServerResponse;

                // Re-new when we're about to reach the TTL
                refreshTURNServerTimer = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:turnServerResponse.ttl * 0.9]
                                                                  interval:0
                                                                    target:self
                                                                  selector:@selector(refreshTURNServer)
                                                                  userInfo:nil
                                                                   repeats:NO];
                [[NSRunLoop mainRunLoop] addTimer:refreshTURNServerTimer forMode:NSDefaultRunLoopMode];
            }
            else
            {
                NSLog(@"No TURN server: using fallback STUN server: %@", _fallbackSTUNServer);
                _turnServers = nil;
            }
        }

    } failure:^(NSError *error) {
        NSLog(@"[MXCallManager] refreshTURNServer: Failed to get TURN URIs. Error: %@\n", error);
        if (calls)
        {
            NSLog(@"Retry in 60s");
            refreshTURNServerTimer = [NSTimer timerWithTimeInterval:60 target:self selector:@selector(refreshTURNServer) userInfo:nil repeats:NO];
        }
    }];
}

- (void)handleCallInvite:(MXEvent*)event
{
    MXCallInviteEventContent *content = [MXCallInviteEventContent modelFromJSON:event.content];

    // Check expiration (usefull filter when receiving load of events when resuming the event stream)
    if (event.age < content.lifetime)
    {
        // If it is an invite from the peer, we need to create the MXCall
        if (NO == [event.sender isEqualToString:_mxSession.myUser.userId])
        {
            MXCall *call = [self callWithCallId:content.callId];
            if (nil == call)
            {
                call = [[MXCall alloc] initWithRoomId:event.roomId andCallManager:self];
                if (call)
                {
                    [calls addObject:call];

                    [call handleCallEvent:event];

                    // Broadcast the incoming call
                    [self notifyCallInvite:call.callId];
                }
            }
            else
            {
                [call handleCallEvent:event];
            }
        }
    }
}

- (void)notifyCallInvite:(NSString*)callId
{
    MXCall *call = [self callWithCallId:callId];

    if (call)
    {
        // If the app is resuming, wait for the complete end of the session resume in order
        // to check if the invite is still valid
        if (_mxSession.state != MXSessionStateRunning)
        {
            // The dispatch  on the main thread should be enough.
            // It means that the sync response that contained the invite (and possibly its end
            // of validity) has been fully parsed.
            __weak typeof(self) weakSelf = self;
            dispatch_async(dispatch_get_main_queue(), ^{

                __strong __typeof(weakSelf)strongSelf = weakSelf;
                if (strongSelf)
                {
                    [strongSelf notifyCallInvite:callId];
                }
            });
        }
        else if (call.state < MXCallStateConnected)
        {
            // If the call is still in ringing state, notify the app
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXCallManagerNewCall object:call userInfo:nil];
        }
    }
}

- (void)handleCallAnswer:(MXEvent*)event
{
    MXCallAnswerEventContent *content = [MXCallAnswerEventContent modelFromJSON:event.content];

    MXCall *call = [self callWithCallId:content.callId];
    if (call)
    {
        [call handleCallEvent:event];
    }
}

- (void)handleCallHangup:(MXEvent*)event
{
    MXCallHangupEventContent *content = [MXCallHangupEventContent modelFromJSON:event.content];

    // Forward the event to the MXCall object
    MXCall *call = [self callWithCallId:content.callId];
    if (call)
    {
        [call handleCallEvent:event];
    }

    // Forget this call. It is no more in progress
    [calls removeObject:call];
}

- (void)handleCallCandidates:(MXEvent*)event
{
    MXCallCandidatesEventContent *content = [MXCallCandidatesEventContent modelFromJSON:event.content];

    // Forward the event to the MXCall object
    MXCall *call = [self callWithCallId:content.callId];
    if (call)
    {
        [call handleCallEvent:event];
    }
}

#pragma mark - Conference call

// Copied from vector-web:
// FIXME: This currently forces Vector to try to hit the matrix.org AS for conferencing.
// This is bad because it prevents people running their own ASes from being used.
// This isn't permanent and will be customisable in the future: see the proposal
// at docs/conferencing.md for more info.
#define USER_PREFIX @"fs_"
#define DOMAIN      @"matrix.org"

/**
 Return the id of the conference user dedicated for the passed room.

 @param roomId the room id.
 @return the conference user id.
 */
+ (NSString*)conferenceUserIdForRoom:(NSString*)roomId
{
    // Apply the same algo as other matrix clients
    NSString *base64RoomId = [[roomId dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    base64RoomId = [base64RoomId stringByReplacingOccurrencesOfString:@"=" withString:@""];

    return [NSString stringWithFormat:@"@%@%@:%@", USER_PREFIX, base64RoomId, DOMAIN];
}


/**
 Make sure the conference user is in the passed room.

 It is mandatory before starting the conference call.

 @param room the room.
 @return the conference user id.
 */
- (void)inviteConferenceUserToRoom:(MXRoom*)room
                           success:(void (^)())success
                           failure:(void (^)(NSError *error))failure
{
    NSString *conferenceUserId = [MXCallManager conferenceUserIdForRoom:room.roomId];

    MXRoomMember *conferenceUserMember = [room.state memberWithUserId:conferenceUserId];
    if (conferenceUserMember && conferenceUserMember.membership == MXMembershipJoin)
    {
        success();
    }
    else
    {
        [room inviteUser:conferenceUserId success:success failure:failure];
    }
}

/**
 Get the room with the conference user dedicated for the passed room.

 @param roomId the room id.
 @return the private room with conference user.
 */
- (void)conferenceUserRoomForRoom:(NSString*)roomId
                          success:(void (^)(MXRoom *conferenceUserRoom))success
                          failure:(void (^)(NSError *error))failure
{
    NSString *conferenceUserId = [MXCallManager conferenceUserIdForRoom:roomId];

    // Use an existing 1:1 with the conference user; else make one
    MXRoom *conferenceUserRoom;
    for (MXRoom *room in _mxSession.rooms)
    {
        if (room.state.members.count == 2 && [room.state memberWithUserId:conferenceUserId])
        {
            conferenceUserRoom = room;
        }
    }

    if (conferenceUserRoom)
    {
        success(conferenceUserRoom);
    }
    else
    {
        [_mxSession createRoom:@{
                                 @"preset": @"private_chat",
                                 @"invite": @[conferenceUserId]
                                } success:^(MXRoom *room) {

                                    success(room);

                                } failure:failure];
    }
}

@end

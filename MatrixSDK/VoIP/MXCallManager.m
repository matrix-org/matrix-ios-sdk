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
        if ([call.room.state.roomId isEqualToString:roomId])
        {
            theCall = call;
            break;
        }
    }
    return theCall;
}

- (MXCall *)placeCallInRoom:(NSString *)roomId withVideo:(BOOL)video
{
    MXCall *call;

    MXRoom *room = [_mxSession roomWithRoomId:roomId];

    if (room && 2 == room.state.joinedMembers.count)
    {
        call = [[MXCall alloc] initWithRoomId:roomId andCallManager:self];
        if (call)
        {
            [calls addObject:call];

            [call callWithVideo:video];

            // Broadcast the new outgoing call
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXCallManagerNewCall object:call userInfo:nil];
        }
    }
    else
    {
        NSLog(@"[MXCallManager] placeCallInRoom: ERROR: Cannot place call in %@. Members count: %tu", roomId, room.state.joinedMembers.count);
    }

    return call;
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

@end

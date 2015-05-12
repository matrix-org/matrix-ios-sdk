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

#import "MXCall.h"

#import "MXSession.h"
#import "MXCallStackCall.h"

@interface MXCall ()
{
    /**
     The manager of this object.
     */
    MXCallManager *callManager;

    /**
     The call object managed by the call stack
     */
    id<MXCallStackCall> callStackCall;

    /**
     The invite received by the peer
     */
    MXCallInviteEventContent *callInviteEventContent;

    /**
     The date when the communication has been established.
     */
    NSDate *callConnectedDate;

    /**
     The total duration of the call. It is computed when the call ends.
     */
    NSUInteger totalCallDuration;
}

@end

@implementation MXCall

- (instancetype)initWithRoomId:(NSString *)roomId andCallManager:(MXCallManager *)callManager2
{
    self = [super init];
    if (self)
    {
        callManager = callManager2;

        _room = [callManager.mxSession roomWithRoomId:roomId];

        _callId = [[NSUUID UUID] UUIDString];
        _callerId = callManager.mxSession.myUser.userId;

        _state = MXCallStateFledgling;

        callStackCall = [callManager.callStack createCall];
        if (nil == callStackCall)
        {
            NSLog(@"[MXCall] Error: Cannot create call. [MXCallStack createCall] returned nil.");
            return nil;
        }

        // Set up TURN/STUN servers
        if (callManager.turnServers)
        {
            [callStackCall addTURNServerUris:callManager.turnServers.uris
                                        withUsername:callManager.turnServers.username
                                            password:callManager.turnServers.password];
        }
        else
        {
            NSLog(@"[MXCall] No TURN server: using fallback STUN server: %@", callManager.fallbackSTUNServer);
            [callStackCall addTURNServerUris:@[callManager.fallbackSTUNServer] withUsername:nil password:nil];
        }
    }
    return self;
}

- (void)handleCallEvent:(MXEvent *)event
{
    switch (event.eventType)
    {
        case MXEventTypeCallInvite:
        {
            callInviteEventContent = [MXCallInviteEventContent modelFromJSON:event.content];

            _callId = callInviteEventContent.callId;
            _callerId = event.userId;
            _isIncoming = YES;

            // Determine if it is voice or video call
            if (NSNotFound != [callInviteEventContent.offer.sdp rangeOfString:@"m=video"].location)
            {
                _isVideoCall = YES;
            }

            [self setState:MXCallStateRinging reason:event];
            break;
        }

        case MXEventTypeCallAnswer:
        {
            // MXCall receives this event only when it placed a call
            MXCallAnswerEventContent *content = [MXCallAnswerEventContent modelFromJSON:event.content];

            // Let's the stack finalise the connection
            [callStackCall handleAnswer:content.answer.sdp success:^{

                // Call is up
                [self setState:MXCallStateConnected reason:event];

            } failure:^(NSError *error) {
                NSLog(@"[MXCall] handleCallEvent: ERROR: Cannot send handle answer. Error: %@\nEvent: %@", error, event);
                [self didEncounterError:error];
            }];
            break;
        }

        case MXEventTypeCallHangup:
        {
            if (_state != MXCallStateEnded)
            {
                [self terminateWithReason:event];
            }
            break;
        }

        case MXEventTypeCallCandidates:
        {
            MXCallCandidatesEventContent *content = [MXCallCandidatesEventContent modelFromJSON:event.content];
            for (NSDictionary *canditate in content.candidates)
            {
                [callStackCall handleRemoteCandidate:canditate];
            }
            break;
        }

        default:
            break;
    }
}


#pragma mark - Controls
- (void)callWithVideo:(BOOL)video
{
    _isIncoming = NO;

    _isVideoCall = video;

    [self setState:MXCallStateWaitLocalMedia reason:nil];

    [callStackCall startCapturingMediaWithVideo:video success:^() {

        [callStackCall createOffer:^(NSString *sdp) {

            [self setState:MXCallStateCreateOffer reason:nil];

            NSLog(@"[MXCallManager] placeCallInRoom. Offer created: %@", sdp);

            // The call invite can sent to the HS
            NSDictionary *content = @{
                                      @"call_id": _callId,
                                      @"offer": @{
                                              @"type": @"offer",
                                              @"sdp": sdp
                                              },
                                      @"version": @(0),
                                      @"lifetime": @(30 * 1000)
                                      };
            [_room sendEventOfType:kMXEventTypeStringCallInvite content:content success:^(NSString *eventId) {

                [self setState:MXCallStateInviteSent reason:nil];

            } failure:^(NSError *error) {
                NSLog(@"[MXCall] callWithVideo: ERROR: Cannot send m.call.invite event. Error: %@", error);
                [self didEncounterError:error];
            }];

        } failure:^(NSError *error) {
            NSLog(@"[MXCall] callWithVideo: ERROR: Cannot create offer. Error: %@", error);
            [self didEncounterError:error];
        }];
    } failure:^(NSError *error) {
        NSLog(@"[MXCall] callWithVideo: ERROR: Cannot start capturing media. Error: %@", error);
        [self didEncounterError:error];
    }];
}

- (void)answer
{
    if (self.state == MXCallStateRinging)
    {
        [self setState:MXCallStateWaitLocalMedia reason:nil];

        [callStackCall startCapturingMediaWithVideo:self.isVideoCall success:^{

            // Create a sdp answer from the offer we got
            [self setState:MXCallStateCreateAnswer reason:nil];
            [self setState:MXCallStateConnecting reason:nil];

            [callStackCall handleOffer:callInviteEventContent.offer.sdp success:^(NSString *sdpAnswer) {

                // The call invite can sent to the HS
                NSDictionary *content = @{
                                          @"call_id": _callId,
                                          @"answer": @{
                                                  @"type": @"answer",
                                                  @"sdp": sdpAnswer
                                                  },
                                          @"version": @(0),
                                          };
                [_room sendEventOfType:kMXEventTypeStringCallAnswer content:content success:^(NSString *eventId) {

                    [self setState:MXCallStateConnected reason:nil];

                } failure:^(NSError *error) {
                    NSLog(@"[MXCall] answer: ERROR: Cannot send m.call.answer event. Error: %@", error);
                    [self didEncounterError:error];
                }];
                
            } failure:^(NSError *error) {
                NSLog(@"[MXCall] answer: ERROR: Cannot create offer. Error: %@", error);
                [self didEncounterError:error];
            }];
            
            callInviteEventContent = nil;

        } failure:^(NSError *error) {
            NSLog(@"[MXCall] answer: ERROR: Cannot start capturing media. Error: %@", error);
            [self didEncounterError:error];
        }];
    }
}

- (void)hangup
{
    if (self.state != MXCallStateEnded)
    {
        [self terminateWithReason:nil];

        // Send the hangup event
        NSDictionary *content = @{
                                  @"call_id": _callId,
                                  @"version": @(0)
                                  };
        [_room sendEventOfType:kMXEventTypeStringCallHangup content:content success:nil failure:^(NSError *error) {
            NSLog(@"[MXCall] hangup: ERROR: Cannot send m.call.hangup event. Error: %@", error);
            [self didEncounterError:error];
        }];
    }
}


#pragma marl - Properties
- (void)setState:(MXCallState)state reason:(MXEvent*)event
{
    // Manage call duration
    if (MXCallStateConnected == state)
    {
        // Set the start point
        callConnectedDate = [NSDate date];
    }
    else if (MXCallStateEnded == state)
    {
        // Store the total duration
        totalCallDuration = self.duration;
    }

    _state = state;

    if (_delegate)
    {
        [_delegate call:self stateDidChange:_state reason:event];
    }
}

- (void)setSelfVideoView:(UIView *)selfVideoView
{
    if (selfVideoView != _selfVideoView)
    {
        _selfVideoView = selfVideoView;
        callStackCall.selfVideoView = selfVideoView;
    }
}

- (void)setRemoteVideoView:(UIView *)remoteVideoView
{
    if (remoteVideoView != _remoteVideoView)
    {
        _remoteVideoView = remoteVideoView;
        callStackCall.remoteVideoView = remoteVideoView;
    }
}

- (NSUInteger)duration
{
    NSUInteger duration = 0;

    if (MXCallStateConnected == _state)
    {
        duration = [[NSDate date] timeIntervalSinceDate:callConnectedDate] * 1000;
    }
    else if (MXCallStateEnded == _state)
    {
        duration = totalCallDuration;
    }
    return duration;
}


#pragma mark - Private methods
- (void)terminateWithReason:(MXEvent*)event
{
    // Terminate the call at the stack level
    [callStackCall terminate];

    [self setState:MXCallStateEnded reason:event];
}

- (void)didEncounterError:(NSError*)error
{
    if ([_delegate performSelector:@selector(call:didEncounterError:)])
    {
        [_delegate call:self didEncounterError:error];
    }
}

@end

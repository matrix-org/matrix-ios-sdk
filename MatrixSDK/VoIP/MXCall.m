/*
 Copyright 2015 OpenMarket Ltd
 Copyright 2018 New Vector Ltd
 Copyright 2019 The Matrix.org Foundation C.I.C

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

#import "MXCallStack.h"
#import "MXEvent.h"
#import "MXSession.h"
#import "MXTools.h"
#import "MXSDKOptions.h"
#import "MXEnumConstants.h"

#import "MXCallInviteEventContent.h"
#import "MXCallAnswerEventContent.h"
#import "MXCallSelectAnswerEventContent.h"
#import "MXCallCandidatesEventContent.h"
#import "MXCallRejectEventContent.h"
#import "MXCallNegotiateEventContent.h"
#import "MXCallReplacesEventContent.h"
#import "MXCallRejectReplacementEventContent.h"
#import "MXUserModel.h"
#import "MXCallCapabilitiesModel.h"

#pragma mark - Constants definitions
NSString *const kMXCallStateDidChange = @"kMXCallStateDidChange";
NSString *const kMXCallSupportsHoldingStatusDidChange = @"kMXCallSupportsHoldingStatusDidChange";
NSString *const kMXCallSupportsTransferringStatusDidChange = @"kMXCallSupportsTransferringStatusDidChange";

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
     The invite sent to/received by the peer
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

    /**
     Timer to expire an invite.
     */
    NSTimer *inviteExpirationTimer;

    /**
     A queue of gathered local ICE candidates waiting to be sent to the other peer.
     */
    NSMutableArray<NSDictionary *> *localICECandidates;

    /**
     Timer for sending local ICE candidates.
     */
    NSTimer *localIceGatheringTimer;

    /**
     Cache for self.calleeId.
     */
    NSString *calleeId;
}

/**
 Selected answer for this call. Can be nil.
 */
@property (nonatomic, strong) MXEvent *selectedAnswer;

@end

@implementation MXCall

@synthesize partyId = _partyId;

- (instancetype)initWithRoomId:(NSString *)roomId andCallManager:(MXCallManager *)theCallManager
{
    // For 1:1 call, use the room as the call signaling room
    return [self initWithRoomId:roomId callSignalingRoomId:roomId andCallManager:theCallManager];
}

- (instancetype)initWithRoomId:(NSString *)roomId callSignalingRoomId:(NSString *)callSignalingRoomId andCallManager:(MXCallManager *)theCallManager;
{
    self = [super init];
    if (self)
    {
        callManager = theCallManager;

        _room = [callManager.mxSession roomWithRoomId:roomId];
        _callSignalingRoom = [callManager.mxSession roomWithRoomId:callSignalingRoomId];

        _callId = [[NSUUID UUID] UUIDString];
        _callUUID = [NSUUID UUID];
        _callerId = callManager.mxSession.myUserId;

        _state = MXCallStateFledgling;
        _endReason = MXCallEndReasonUnknown;

        // Consider we are using a conference call when there are more than 2 users
        _isConferenceCall = (2 < _room.summary.membersCount.joined);

        localICECandidates = [NSMutableArray array];

        // Prevent the session from being paused so that the client can send call matrix
        // events to the other peer to establish the call  even if the app goes in background
        // meanwhile
        [callManager.mxSession retainPreventPause];

        callStackCall = [callManager.callStack createCall];
        if (nil == callStackCall)
        {
            NSLog(@"[MXCall] Error: Cannot create call. [MXCallStack createCall] returned nil.");
            [callManager.mxSession releasePreventPause];
            return nil;
        }

        callStackCall.delegate = self;

        // Set up TURN/STUN servers
        if (callManager.turnServers)
        {
            [callStackCall addTURNServerUris:callManager.turnServers.uris
                                withUsername:callManager.turnServers.username
                                    password:callManager.turnServers.password];
        }
        else if (callManager.fallbackSTUNServer)
        {
            NSLog(@"[MXCall] No TURN server: using fallback STUN server: %@", callManager.fallbackSTUNServer);
            [callStackCall addTURNServerUris:@[callManager.fallbackSTUNServer] withUsername:nil password:nil];
        }
        else
        {
            NSLog(@"[MXCall] No TURN server and no fallback STUN server");

            // Setup the call with no STUN server
            [callStackCall addTURNServerUris:nil withUsername:nil password:nil];
        }
    }
    return self;
}

- (NSString *)partyId
{
    if (_partyId == nil)
    {
        _partyId = callManager.mxSession.myDeviceId;
    }
    return _partyId;
}

- (void)calleeId:(void (^)(NSString * _Nonnull))onComplete
{
    if (calleeId)
    {
        onComplete(calleeId);
    }
    else
    {
        // Set caleeId only for regular calls
        if (!_isConferenceCall)
        {
            MXWeakify(self);
            [_room state:^(MXRoomState *roomState) {
                MXStrongifyAndReturnIfNil(self);

                MXRoomMembers *roomMembers = roomState.members;
                for (MXRoomMember *roomMember in roomMembers.joinedMembers)
                {
                    if (![roomMember.userId isEqualToString:self.callerId])
                    {
                        self->calleeId = roomMember.userId;
                        break;
                    }
                }

                onComplete(self->calleeId);
            }];
        }
    }
}

- (void)handleCallEvent:(MXEvent *)event
{
    switch (event.eventType)
    {
        case MXEventTypeCallInvite:
            [self handleCallInvite:event];
            break;
        case MXEventTypeCallAnswer:
            [self handleCallAnswer:event];
            break;
        case MXEventTypeCallSelectAnswer:
            [self handleCallSelectAnswer:event];
            break;
        case MXEventTypeCallHangup:
            [self handleCallHangup:event];
            break;
        case MXEventTypeCallCandidates:
            [self handleCallCandidates:event];
            break;
        case MXEventTypeCallReject:
            [self handleCallReject:event];
            break;
        case MXEventTypeCallNegotiate:
            [self handleCallNegotiate:event];
            break;
        case MXEventTypeCallReplaces:
            [self handleCallReplaces:event];
            break;
        case MXEventTypeCallRejectReplacement:
            [self handleCallRejectReplacement:event];
            break;
        default:
            break;
    }
}

#pragma mark - Controls
- (void)callWithVideo:(BOOL)video
{
    NSLog(@"[MXCall] callWithVideo");
    
    _isIncoming = NO;

    _isVideoCall = video;

    // Set up the default audio route
    callStackCall.audioToSpeaker = _isVideoCall;
    
    [self setState:MXCallStateWaitLocalMedia reason:nil];
    
    NSString *eventName = _isConferenceCall ? kMXAnalyticsVoipNamePlaceConferenceCall : kMXAnalyticsVoipNamePlaceCall;
    
    [[MXSDKOptions sharedInstance].analyticsDelegate trackValue:@(video)
                                                       category:kMXAnalyticsVoipCategory
                                                           name:eventName];

    MXWeakify(self);
    [callStackCall startCapturingMediaWithVideo:video success:^() {
        MXStrongifyAndReturnIfNil(self);

        MXWeakify(self);
        [self->callStackCall createOffer:^(NSString *sdp) {
            MXStrongifyAndReturnIfNil(self);

            [self setState:MXCallStateCreateOffer reason:nil];

            NSLog(@"[MXCall] callWithVideo:%@ - Offer created: %@", (video ? @"YES" : @"NO"), sdp);

            // The call invite can sent to the HS
            NSMutableDictionary *content = [@{
                @"call_id": self.callId,
                @"offer": @{
                        @"type": kMXCallSessionDescriptionTypeStringOffer,
                        @"sdp": sdp
                },
                @"version": kMXCallVersion,
                @"lifetime": @(self->callManager.inviteLifetime),
                @"capabilities": @{@"m.call.transferee": @(NO)},    //  transferring will be disabled until we have a test bridge
                @"party_id": self.partyId
            } mutableCopy];
            
            NSString *directUserId = self.room.directUserId;
            if (directUserId)
            {
                content[@"invitee"] = directUserId;
            }
            
            [self.callSignalingRoom sendEventOfType:kMXEventTypeStringCallInvite content:content localEcho:nil success:^(NSString *eventId) {

                self->callInviteEventContent = [MXCallInviteEventContent modelFromJSON:content];
                [self setState:MXCallStateInviteSent reason:nil];

            } failure:^(NSError *error) {
                NSLog(@"[MXCall] callWithVideo: ERROR: Cannot send m.call.invite event.");
                [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
            }];

        } failure:^(NSError *error) {
            NSLog(@"[MXCall] callWithVideo: ERROR: Cannot create offer. Error: %@", error);
            [self didEncounterError:error reason:MXCallHangupReasonIceFailed];
        }];
    } failure:^(NSError *error) {
        NSLog(@"[MXCall] callWithVideo: ERROR: Cannot start capturing media. Error: %@", error);
        [self didEncounterError:error reason:MXCallHangupReasonUserMediaFailed];
    }];
}

- (void)answer
{
    NSLog(@"[MXCall] answer");

    // Sanity check on the call state
    // Note that e2e rooms requires several attempts of [MXCall answer] in case of unknown devices 
    if (self.state == MXCallStateRinging
        || (_callSignalingRoom.summary.isEncrypted && self.state == MXCallStateCreateAnswer))
    {
        [self setState:MXCallStateCreateAnswer reason:nil];

        MXWeakify(self);
        void(^answer)(void) = ^{
            MXStrongifyAndReturnIfNil(self);

            NSLog(@"[MXCall] answer: answering...");

            // The incoming call is accepted
            if (self->inviteExpirationTimer)
            {
                [self->inviteExpirationTimer invalidate];
                self->inviteExpirationTimer = nil;
            }

            // Create a sdp answer from the offer we got
            [self setState:MXCallStateConnecting reason:nil];

            MXWeakify(self);
            [self->callStackCall createAnswer:^(NSString *sdpAnswer) {
                MXStrongifyAndReturnIfNil(self);

                NSLog(@"[MXCall] answer - Created SDP:\n%@", sdpAnswer);

                // The call invite can sent to the HS
                NSDictionary *content = @{
                                          @"call_id": self.callId,
                                          @"answer": @{
                                                  @"type": kMXCallSessionDescriptionTypeStringAnswer,
                                                  @"sdp": sdpAnswer
                                                  },
                                          @"capabilities": @{@"m.call.transferee": @(NO)},  //  transferring will be disabled until we have a test bridge
                                          @"version": kMXCallVersion,
                                          @"party_id": self.partyId
                                          };
                [self.callSignalingRoom sendEventOfType:kMXEventTypeStringCallAnswer content:content localEcho:nil success:^(NSString *eventId){
                    //  assume for now, this is the selected answer
                    self.selectedAnswer = [MXEvent modelFromJSON:@{
                        @"event_id": eventId,
                        @"sender": self.callSignalingRoom.mxSession.myUserId,
                        @"room_id": self.callSignalingRoom.roomId,
                        @"type": kMXEventTypeStringCallAnswer,
                        @"content": content
                    }];
                } failure:^(NSError *error) {
                    NSLog(@"[MXCall] answer: ERROR: Cannot send m.call.answer event.");
                    [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
                }];

            } failure:^(NSError *error) {
                NSLog(@"[MXCall] answer: ERROR: Cannot create answer. Error: %@", error);
                [self didEncounterError:error reason:MXCallHangupReasonIceFailed];
            }];
        };

        // If the room is encrypted, we need to check that encryption is set up
        // in the room before actually answering.
        // That will allow MXCall to send ICE candidates events without encryption errors like
        // MXEncryptingErrorUnknownDeviceReason.
        if (_callSignalingRoom.summary.isEncrypted)
        {
            NSLog(@"[MXCall] answer: ensuring encryption is ready to use ...");
            [callManager.mxSession.crypto ensureEncryptionInRoom:_callSignalingRoom.roomId success:answer failure:^(NSError *error) {
                NSLog(@"[MXCall] answer: ERROR: [MXCrypto ensureEncryptionInRoom] failed. Error: %@", error);
                [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
            }];
        }
        else
        {
            answer();
        }
    }
}

- (void)hangup
{
    NSLog(@"[MXCall] hangup");
    
    if (self.state == MXCallStateRinging && [callInviteEventContent.version isEqualToString:kMXCallVersion])
    {
        // Send the reject event for new call invites
        NSDictionary *content = @{
                                  @"call_id": _callId,
                                  @"version": kMXCallVersion,
                                  @"party_id": self.partyId
                                  };
        
        [_callSignalingRoom sendEventOfType:kMXEventTypeStringCallReject content:content localEcho:nil success:nil failure:^(NSError *error) {
            NSLog(@"[MXCall] hangup: ERROR: Cannot send m.call.reject event.");
            [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
        }];
        
        //  terminate with a fake reject event
        MXEvent *fakeEvent = [MXEvent modelFromJSON:@{
            @"type": kMXEventTypeStringCallReject,
            @"content": content
        }];
        fakeEvent.sender = callManager.mxSession.myUserId;
        [self terminateWithReason:fakeEvent];
        return;
    }

    //  hangup with the default reason
    [self hangupWithReason:MXCallHangupReasonUserHangup];
}

- (void)hangupWithReason:(MXCallHangupReason)reason
{
    NSLog(@"[MXCall] hangupWithReason: %ld", (long)reason);
    
    if (self.state != MXCallStateEnded)
    {
        // Send the hangup event
        NSDictionary *content = @{
                                  @"call_id": _callId,
                                  @"version": kMXCallVersion,
                                  @"party_id": self.partyId,
                                  @"reason": [MXTools callHangupReasonString:reason]
                                  };
        [_callSignalingRoom sendEventOfType:kMXEventTypeStringCallHangup content:content localEcho:nil success:^(NSString *eventId) {
            [[MXSDKOptions sharedInstance].analyticsDelegate trackValue:@(reason)
                                                               category:kMXAnalyticsVoipCategory
                                                                   name:kMXAnalyticsVoipNameCallHangup];
        } failure:^(NSError *error) {
            NSLog(@"[MXCall] hangupWithReason: ERROR: Cannot send m.call.hangup event.");
            [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
        }];
        
        //  terminate with a fake hangup event
        MXEvent *fakeEvent = [MXEvent modelFromJSON:@{
            @"type": kMXEventTypeStringCallHangup,
            @"content": content
        }];
        fakeEvent.sender = callManager.mxSession.myUserId;
        [self terminateWithReason:fakeEvent];
    }
}

#pragma mark - Hold

- (BOOL)supportsHolding
{
    if (callInviteEventContent && _selectedAnswer && [callInviteEventContent.version isEqualToString:kMXCallVersion])
    {
        MXCallAnswerEventContent *content = [MXCallAnswerEventContent modelFromJSON:_selectedAnswer.content];
        return [content.version isEqualToString:kMXCallVersion];
    }
    return NO;
}

- (void)hold:(BOOL)hold
{
    if (_state < MXCallStateConnected)
    {
        //  call not connected yet, cannot be holded/unholded
        return;
    }
    
    if (hold)
    {
        if (_state == MXCallStateOnHold || _state == MXCallStateRemotelyOnHold)
        {
            //  already holded
            return;
        }
    }
    else
    {
        if (_state == MXCallStateRemotelyOnHold)
        {
            //  remotely holded calls cannot be unholded
            return;
        }
        if (_state == MXCallStateConnected)
        {
            //  already connected
            return;
        }
    }
    
    MXWeakify(self);
    [callStackCall hold:hold success:^(NSString * _Nonnull sdp) {
        MXStrongifyAndReturnIfNil(self);
        
        NSLog(@"[MXCall] hold: %@ offer created: %@", (hold ? @"Hold" : @"Resume"), sdp);

        // The call hold offer can sent to the HS
        NSMutableDictionary *content = [@{
            @"call_id": self.callId,
            @"description": @{
                    @"type": kMXCallSessionDescriptionTypeStringOffer,
                    @"sdp": sdp
            },
            @"version": kMXCallVersion,
            @"lifetime": @(self->callManager.negotiateLifetime),
            @"party_id": self.partyId
        } mutableCopy];
        
        [self.callSignalingRoom sendEventOfType:kMXEventTypeStringCallNegotiate content:content localEcho:nil success:^(NSString *eventId) {

            if (hold)
            {
                [self setState:MXCallStateOnHold reason:nil];
            }
            else
            {
                [self setState:MXCallStateConnected reason:nil];
            }

        } failure:^(NSError *error) {
            NSLog(@"[MXCall] hold: ERROR: Cannot send m.call.negotiate event.");
            [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
        }];
        
    } failure:^(NSError * _Nonnull error) {
        NSLog(@"[MXCall] hold: ERROR: Cannot create %@ offer. Error: %@", (hold ? @"Hold" : @"Resume"), error);
        [self didEncounterError:error reason:MXCallHangupReasonIceFailed];
    }];
}

- (BOOL)isOnHold
{
    return _state == MXCallStateOnHold || _state == MXCallStateRemotelyOnHold;
}

#pragma mark - Transfer

- (BOOL)supportsTransferring
{
    if (callInviteEventContent && _selectedAnswer)
    {
        MXCallAnswerEventContent *content = [MXCallAnswerEventContent modelFromJSON:_selectedAnswer.content];
        return callInviteEventContent.capabilities.transferee && content.capabilities.transferee;
    }
    return NO;
}

- (void)transferToRoom:(NSString * _Nullable)targetRoomId
                  user:(MXUserModel * _Nullable)targetUser
            createCall:(NSString * _Nullable)createCallId
             awaitCall:(NSString * _Nullable)awaitCallId
               success:(void (^)(NSString * _Nonnull eventId))success
               failure:(void (^)(NSError * _Nullable error))failure
{
    MXCallReplacesEventContent *content = [[MXCallReplacesEventContent alloc] init];
    
    //  base fields
    content.callId = self.callId;
    content.versionString = kMXCallVersion;
    content.partyId = self.partyId;
    
    //  other fields
    content.replacementId = [[NSUUID UUID] UUIDString];
    content.lifetime = self->callManager.transferLifetime;
    
    if (targetRoomId)
    {
        content.targetRoomId = targetRoomId;
    }
    if (targetUser)
    {
        content.targetUser = targetUser;
    }
    if (createCallId)
    {
        content.createCallId = createCallId;
    }
    if (awaitCallId)
    {
        content.awaitCallId = awaitCallId;
    }
    
    [self.callSignalingRoom sendEventOfType:kMXEventTypeStringCallReplaces
                                    content:content.JSONDictionary
                                  localEcho:nil
                                    success:success
                                    failure:^(NSError *error) {
        NSLog(@"[MXCall] transferToRoom: ERROR: Cannot send m.call.replaces event.");
        if (failure)
        {
            failure(error);
        }
    }];
}

#pragma mark - DTMF

- (BOOL)supportsDTMF
{
    return [callStackCall canSendDTMF];
}

- (BOOL)sendDTMF:(NSString * _Nonnull)tones
        duration:(NSUInteger)duration
    interToneGap:(NSUInteger)interToneGap
{
    return [callStackCall sendDTMF:tones duration:duration interToneGap:interToneGap];
}

#pragma mark - Properties

- (void)setSelectedAnswer:(MXEvent *)selectedAnswer
{
    if (_selectedAnswer == selectedAnswer)
    {
        //  already the same, ignore it
        return;
    }
    
    _selectedAnswer = selectedAnswer;
    
    if ([_delegate respondsToSelector:@selector(callSupportsHoldingStatusDidChange:)])
    {
        [_delegate callSupportsHoldingStatusDidChange:self];
    }
    
    if ([_delegate respondsToSelector:@selector(callSupportsTransferringStatusDidChange:)])
    {
        [_delegate callSupportsTransferringStatusDidChange:self];
    }
    
    // Broadcast the new call statuses
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kMXCallSupportsHoldingStatusDidChange
                                                        object:self
                                                      userInfo:nil];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kMXCallSupportsTransferringStatusDidChange
                                                        object:self
                                                      userInfo:nil];
}

- (void)setState:(MXCallState)state reason:(MXEvent *)event
{
    NSLog(@"[MXCall] setState. old: %@. New: %@", @(_state), @(state));

    // Manage call duration
    if (MXCallStateConnected == state)
    {
        if (_state != MXCallStateOnHold && _state != MXCallStateRemotelyOnHold)
        {
            // Set the start point
            callConnectedDate = [NSDate date];
            
            // Mark call as established
            _established = YES;
        }
    }
    else if (MXCallStateEnded == state)
    {
        // Release the session pause prevention 
        [callManager.mxSession releasePreventPause];

        // Store the total duration
        totalCallDuration = self.duration;
        
        [[MXSDKOptions sharedInstance].analyticsDelegate trackValue:@(_endReason)
                                                           category:kMXAnalyticsVoipCategory
                                                               name:kMXAnalyticsVoipNameCallEnded];
        
        // Terminate the call at the stack level
        [callStackCall end];
    }
    else if (MXCallStateInviteSent == state)
    {
        // Start the life expiration timer for the sent invitation
        inviteExpirationTimer = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:callManager.inviteLifetime / 1000]
                                                         interval:0
                                                           target:self
                                                         selector:@selector(expireCallInvite)
                                                         userInfo:nil
                                                          repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:inviteExpirationTimer forMode:NSDefaultRunLoopMode];
    }

    _state = state;

    if (_delegate)
    {
        [_delegate call:self stateDidChange:_state reason:event];
    }

    // Broadcast the new call state
    [[NSNotificationCenter defaultCenter] postNotificationName:kMXCallStateDidChange object:self userInfo:nil];
}

#if TARGET_OS_IPHONE
- (void)setSelfVideoView:(nullable UIView *)selfVideoView
#elif TARGET_OS_OSX
- (void)setSelfVideoView:(nullable NSView *)selfVideoView
#endif
{
    if (selfVideoView != _selfVideoView)
    {
        _selfVideoView = selfVideoView;
        callStackCall.selfVideoView = selfVideoView;
    }
}

#if TARGET_OS_IPHONE
- (void)setRemoteVideoView:(nullable UIView *)remoteVideoView
#elif TARGET_OS_OSX
- (void)setRemoteVideoView:(nullable NSView *)remoteVideoView
#endif
{
    if (remoteVideoView != _remoteVideoView)
    {
        _remoteVideoView = remoteVideoView;
        callStackCall.remoteVideoView = remoteVideoView;
    }
}

#if TARGET_OS_IPHONE
- (UIDeviceOrientation)selfOrientation
{
    return callStackCall.selfOrientation;
}
#endif

#if TARGET_OS_IPHONE
- (void)setSelfOrientation:(UIDeviceOrientation)selfOrientation
{
    if (callStackCall.selfOrientation != selfOrientation)
    {
        callStackCall.selfOrientation = selfOrientation;
    }
}
#endif

- (BOOL)audioMuted
{
    return callStackCall.audioMuted;
}

- (void)setAudioMuted:(BOOL)audioMuted
{
    callStackCall.audioMuted = audioMuted;
}

- (BOOL)videoMuted
{
    return callStackCall.videoMuted;
}

- (void)setVideoMuted:(BOOL)videoMuted
{
    callStackCall.videoMuted = videoMuted;
}

- (BOOL)audioToSpeaker
{
    return callStackCall.audioToSpeaker;
}

- (void)setAudioToSpeaker:(BOOL)audioToSpeaker
{
    callStackCall.audioToSpeaker = audioToSpeaker;
}

- (AVCaptureDevicePosition)cameraPosition
{
    return callStackCall.cameraPosition;
}

- (void)setCameraPosition:(AVCaptureDevicePosition)cameraPosition
{
    if (cameraPosition != callStackCall.cameraPosition)
    {
        callStackCall.cameraPosition = cameraPosition;
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


#pragma mark - MXCallStackCallDelegate
- (void)callStackCall:(id<MXCallStackCall>)callStackCall onICECandidateWithSdpMid:(NSString *)sdpMid sdpMLineIndex:(NSInteger)sdpMLineIndex candidate:(NSString *)candidate
{
    // Candidates are sent in a special way because we try to amalgamate
    // them into one message
    // No need for locking data as everything is running on the main thread
    [localICECandidates addObject:@{
                                    @"sdpMid": sdpMid,
                                    @"sdpMLineIndex": @(sdpMLineIndex),
                                    @"candidate":candidate
                                    }
     ];

    // Send candidates every 100ms max. This value gives enough time to the underlaying call stack
    // to gather several ICE candidates
    [localIceGatheringTimer invalidate];
    localIceGatheringTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(sendLocalIceCandidates) userInfo:self repeats:NO];
}

- (void)sendLocalIceCandidates
{
    localIceGatheringTimer = nil;

    if (localICECandidates.count)
    {
        NSLog(@"MXCall] onICECandidate: Send %tu candidates", localICECandidates.count);

        NSDictionary *content = @{
                                  @"version": kMXCallVersion,
                                  @"call_id": _callId,
                                  @"candidates": localICECandidates,
                                  @"party_id": self.partyId
                                  };

        [_callSignalingRoom sendEventOfType:kMXEventTypeStringCallCandidates content:content localEcho:nil success:nil failure:^(NSError *error) {
            NSLog(@"[MXCall] onICECandidate: Warning: Cannot send m.call.candidates event.");
            [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
        }];

        [localICECandidates removeAllObjects];
    }
}

- (void)callStackCallDidRemotelyHold:(id<MXCallStackCall>)callStackCall
{
    if (self.state == MXCallStateConnected)
    {
        [self setState:MXCallStateRemotelyOnHold reason:nil];
    }
}

- (void)callStackCall:(id<MXCallStackCall>)callStackCall onError:(NSError *)error
{
    NSLog(@"[MXCall] callStackCall didEncounterError: %@", error);
    
    if (self.isEstablished)
    {
        [self didEncounterError:error reason:MXCallHangupReasonIceTimeout];
    }
    else
    {
        [self didEncounterError:error reason:MXCallHangupReasonIceFailed];
    }
}

- (void)callStackCallDidConnect:(id<MXCallStackCall>)callStackCall
{
    if (self.state == MXCallStateConnecting || self.state == MXCallStateRemotelyOnHold)
    {
        [self setState:MXCallStateConnected reason:nil];
    }
}

#pragma mark - Event Handlers

- (void)handleCallInvite:(MXEvent *)event
{
    callInviteEventContent = [MXCallInviteEventContent modelFromJSON:event.content];
    
    if ([self isMyEvent:event])
    {
        return;
    }

    // Incoming call

    if (_state >= MXCallStateRinging)
    {
        //  already ringing, do nothing
        return;
    }

    _callId = callInviteEventContent.callId;
    _callerId = event.sender;
    calleeId = callManager.mxSession.myUserId;
    _isIncoming = YES;

    // Store if it is voice or video call
    _isVideoCall = callInviteEventContent.isVideoCall;
    
    [[MXSDKOptions sharedInstance].analyticsDelegate trackValue:@(_isVideoCall)
                                                       category:kMXAnalyticsVoipCategory
                                                           name:kMXAnalyticsVoipNameReceiveCall];

    // Set up the default audio route
    callStackCall.audioToSpeaker = _isVideoCall;
    
    [self setState:MXCallStateWaitLocalMedia reason:nil];

    MXWeakify(self);
    [callStackCall startCapturingMediaWithVideo:self.isVideoCall success:^{
        MXStrongifyAndReturnIfNil(self);

        MXWeakify(self);
        [self->callStackCall handleOffer:self->callInviteEventContent.offer.sdp
                           success:^{
                               MXStrongifyAndReturnIfNil(self);

                               // Check whether the call has not been ended.
                               if (self.state != MXCallStateEnded)
                               {
                                   [self setState:MXCallStateRinging reason:event];
                               }
                           }
                           failure:^(NSError * _Nonnull error) {
                               NSLog(@"[MXCall] handleCallInvite: ERROR: Couldn't handle offer. Error: %@", error);
                               [self didEncounterError:error reason:MXCallHangupReasonIceFailed];
                           }];
    } failure:^(NSError *error) {
        NSLog(@"[MXCall] handleCallInvite: startCapturingMediaWithVideo : ERROR: Couldn't start capturing. Error: %@", error);
        [self didEncounterError:error reason:MXCallHangupReasonUserMediaFailed];
    }];

    // Start expiration timer
    inviteExpirationTimer = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:callInviteEventContent.lifetime / 1000]
                                                     interval:0
                                                       target:self
                                                     selector:@selector(expireCallInvite)
                                                     userInfo:nil
                                                      repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:inviteExpirationTimer forMode:NSDefaultRunLoopMode];
}

- (void)handleCallAnswer:(MXEvent *)event
{
    if ([self isMyEvent:event])
    {
        return;
    }
    
    // Listen to answer event only for call we are making, not receiving
    if (!_isIncoming)
    {
        if (_selectedAnswer)
        {
            //  there is already a selected answer, ignore this one
            return;
        }
        
        // MXCall receives this event only when it placed a call
        MXCallAnswerEventContent *content = [MXCallAnswerEventContent modelFromJSON:event.content];

        // The peer accepted our outgoing call
        if (inviteExpirationTimer)
        {
            [inviteExpirationTimer invalidate];
            inviteExpirationTimer = nil;
        }
        
        //  mark this as the selected one
        self.selectedAnswer = event;
        
        void(^continueBlock)(void) = ^{
            // Let's the stack finalise the connection
            [self setState:MXCallStateConnecting reason:event];
            [self->callStackCall handleAnswer:content.answer.sdp
                                success:^{}
                                failure:^(NSError *error) {
                NSLog(@"[MXCall] handleCallAnswer: ERROR: Cannot send handle answer. Error: %@\nEvent: %@", error, event);
                self.selectedAnswer = nil;
                [self didEncounterError:error reason:MXCallHangupReasonIceFailed];
            }];
        };
        
        if ([content.version isEqualToString:kMXCallVersion])
        {
            NSDictionary *selectAnswerContent = @{
                @"call_id": self.callId,
                @"version": kMXCallVersion,
                @"party_id": self.partyId,
                @"selected_party_id": content.partyId
            };
            
            [self.callSignalingRoom sendEventOfType:kMXEventTypeStringCallSelectAnswer
                                            content:selectAnswerContent
                                          localEcho:nil
                                            success:^(NSString *eventId) {
                
                continueBlock();
                
            } failure:^(NSError *error) {
                NSLog(@"[MXCall] handleCallAnswer: ERROR: Cannot send m.call.select_answer event. Error: %@\n", error);
                self.selectedAnswer = nil;
                [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
            }];
        }
        else
        {
            continueBlock();
        }
    }
    else if (_state == MXCallStateRinging)
    {
        // Else this event means that the call has been answered by the user from
        // another device
        [self onCallAnsweredElsewhere];
    }
}

- (void)handleCallSelectAnswer:(MXEvent *)event
{
    if ([self isMyEvent:event])
    {
        return;
    }
    
    if (_isIncoming)
    {
        MXCallSelectAnswerEventContent *content = [MXCallSelectAnswerEventContent modelFromJSON:event.content];
        if (![content.selectedPartyId isEqualToString:self.partyId])
        {
            //  a different answer is selected, also our assumption was wrong
            self.selectedAnswer = nil;
            
            // This means that the call has been answered (accepted/rejected) by another user/device
            [self onCallAnsweredElsewhere];
        }
    }
}

- (void)handleCallHangup:(MXEvent *)event
{
    if (_state != MXCallStateEnded)
    {
        [self terminateWithReason:event];
    }
}

- (void)handleCallCandidates:(MXEvent *)event
{
    if ([self isMyEvent:event])
    {
        return;
    }

    MXCallCandidatesEventContent *content = [MXCallCandidatesEventContent modelFromJSON:event.content];

    NSLog(@"[MXCall] handleCallCandidates: %@", content.candidates);
    for (MXCallCandidate *canditate in content.candidates)
    {
        [callStackCall handleRemoteCandidate:canditate.JSONDictionary];
    }
}

- (void)handleCallReject:(MXEvent *)event
{
    if ([self isMyEvent:event])
    {
        return;
    }
    
    // Listen to answer event only for call we are making, not receiving
    if (!_isIncoming)
    {
        if (_selectedAnswer)
        {
            //  there is already a selected answer, ignore this one
            return;
        }
        
        // The peer rejected our outgoing call
        if (inviteExpirationTimer)
        {
            [inviteExpirationTimer invalidate];
            inviteExpirationTimer = nil;
        }
        
        if (_state != MXCallStateEnded)
        {
            MXCallRejectEventContent *content = [MXCallRejectEventContent modelFromJSON:event.content];
            self.selectedAnswer = event;
            
            NSDictionary *selectAnswerContent = @{
                @"call_id": self.callId,
                @"version": kMXCallVersion,
                @"party_id": self.partyId,
                @"selected_party_id": content.partyId
            };
            
            [self.callSignalingRoom sendEventOfType:kMXEventTypeStringCallSelectAnswer
                                            content:selectAnswerContent
                                          localEcho:nil
                                            success:^(NSString *eventId) {
                
                [self terminateWithReason:event];
                
            } failure:^(NSError *error) {
                NSLog(@"[MXCall] handleCallReject: ERROR: Cannot send m.call.select_answer event. Error: %@\n", error);
                self.selectedAnswer = nil;
                [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
            }];
        }
    }
}

- (void)handleCallNegotiate:(MXEvent *)event
{
    if ([self isMyEvent:event])
    {
        return;
    }
    
    if (![self canHandleNegotiationEvent:event])
    {
        return;
    }
    
    MXCallNegotiateEventContent *content = [MXCallNegotiateEventContent modelFromJSON:event.content];
    
    if (content.sessionDescription.type == MXCallSessionDescriptionTypeOffer)
    {
        // Store if it is voice or video call
        _isVideoCall = content.isVideoCall;

        // Set up the default audio route
        callStackCall.audioToSpeaker = _isVideoCall;
        
        MXWeakify(self);
        [self->callStackCall handleOffer:content.sessionDescription.sdp
                                 success:^{
            MXStrongifyAndReturnIfNil(self);
            
            //  TODO: Get offer type from handleOffer and decide auto-accept it or not
            //  auto-accept negotiations for now
            [self->callStackCall createAnswer:^(NSString * _Nonnull sdpAnswer) {
                MXStrongifyAndReturnIfNil(self);
                
                NSLog(@"[MXCall] handleCallNegotiate: answer negotiation - Created SDP:\n%@", sdpAnswer);
                
                NSDictionary *content = @{
                    @"call_id": self.callId,
                    @"description": @{
                            @"type": kMXCallSessionDescriptionTypeStringAnswer,
                            @"sdp": sdpAnswer
                    },
                    @"version": kMXCallVersion,
                    @"party_id": self.partyId,
                    @"lifetime": @(self->callManager.negotiateLifetime)
                };
                [self.callSignalingRoom sendEventOfType:kMXEventTypeStringCallNegotiate content:content localEcho:nil success:nil failure:^(NSError *error) {
                    NSLog(@"[MXCall] handleCallNegotiate: negotiate answer: ERROR: Cannot send m.call.negotiate event.");
                    [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
                }];
            } failure:^(NSError * _Nonnull error) {
                NSLog(@"[MXCall] handleCallNegotiate: negotiate answer: ERROR: Cannot create negotiate answer. Error: %@", error);
                [self didEncounterError:error reason:MXCallHangupReasonIceFailed];
            }];
        }
                                 failure:^(NSError * _Nonnull error) {
            NSLog(@"[MXCall] handleCallNegotiate: ERROR: Couldn't handle negotiate offer. Error: %@", error);
            [self didEncounterError:error reason:MXCallHangupReasonIceFailed];
        }];
    }
    else if (content.sessionDescription.type == MXCallSessionDescriptionTypeAnswer)
    {
        [self->callStackCall handleAnswer:content.sessionDescription.sdp
                            success:^{}
                            failure:^(NSError *error) {
            NSLog(@"[MXCall] handleCallNegotiate: ERROR: Cannot send handle negotiate answer. Error: %@\nEvent: %@", error, event);
            [self didEncounterError:error reason:MXCallHangupReasonIceFailed];
        }];
    }
}

- (void)handleCallReplaces:(MXEvent *)event
{
    //  TODO: Implement
}

- (void)handleCallRejectReplacement:(MXEvent *)event
{
    //  TODO: Implement
}

#pragma mark - Private methods

- (BOOL)canHandleNegotiationEvent:(MXEvent *)event
{
    if (_isIncoming)
    {
        return YES;
    }
    
    //  outgoing call, check the event coming from the same user with the selected answer
    if (_selectedAnswer && [_selectedAnswer.sender isEqualToString:event.sender])
    {
        MXCallEventContent *selectedAnswerContent = [MXCallEventContent modelFromJSON:_selectedAnswer.content];
        MXCallNegotiateEventContent *content = [MXCallNegotiateEventContent modelFromJSON:event.content];
        
        //  return if user-id and party-id matches
        return [selectedAnswerContent.partyId isEqualToString:content.partyId];
    }
    
    return NO;
}

- (BOOL)isMyEvent:(MXEvent *)event
{
    if ([event.sender isEqualToString:_callSignalingRoom.mxSession.myUserId])
    {
        MXCallEventContent *content = [MXCallEventContent modelFromJSON:event.content];
        return [content.partyId isEqualToString:_callSignalingRoom.mxSession.myDeviceId];
    }
    return NO;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MXCall: %p> id: %@ - isVideoCall: %@ - isIncoming: %@ - state: %@", self, _callId, @(_isVideoCall), @(_isIncoming), @(_state)];
}

- (void)terminateWithReason:(MXEvent *)event
{
    if (inviteExpirationTimer)
    {
        [inviteExpirationTimer invalidate];
        inviteExpirationTimer = nil;
    }

    // Do not refresh TURN servers config anymore
    [localIceGatheringTimer invalidate];
    localIceGatheringTimer = nil;

    // Terminate the call at the stack level
    [callStackCall end];
    
    // Determine call end reason
    if (event)
    {
        switch (event.eventType)
        {
            case MXEventTypeCallHangup:
            {
                MXCallHangupEventContent *content = [MXCallHangupEventContent modelFromJSON:event.content];
                MXCallHangupReason reason = content.reasonType;
                
                switch (reason) 
                {
                    case MXCallHangupReasonUserHangup:
                        if ([event.sender isEqualToString:callManager.mxSession.myUserId])
                        {
                            if ([content.partyId isEqualToString:self.partyId])
                            {
                                _endReason = MXCallEndReasonHangup;
                            }
                            else
                            {
                                _endReason = MXCallEndReasonHangupElsewhere;
                            }
                        }
                        else if (!self.isEstablished && !self.isIncoming)
                        {
                            _endReason = MXCallEndReasonBusy;
                        }
                        else
                        {
                            _endReason = MXCallEndReasonRemoteHangup;
                        }
                        break;
                    case MXCallHangupReasonIceFailed:
                    case MXCallHangupReasonIceTimeout:
                    case MXCallHangupReasonUserMediaFailed:
                    case MXCallHangupReasonUnknownError:
                        _endReason = MXCallEndReasonUnknown;
                        break;
                    case MXCallHangupReasonInviteTimeout:
                        _endReason = MXCallEndReasonMissed;
                        break;
                }
                break;
            }
            case MXEventTypeCallReject:
            {
                _endReason = MXCallEndReasonBusy;
                break;
            }
            default:
            {
                _endReason = MXCallEndReasonHangup;
                break;
            }
        }
    }
    else
    {
        _endReason = MXCallEndReasonHangup;
    }
    
    NSLog(@"[MXCall] terminateWithReason: %@, endReason: %ld", event, (long)_endReason);

    [self setState:MXCallStateEnded reason:event];
}

- (void)didEncounterError:(NSError *)error reason:(MXCallHangupReason)reason
{
    if ([_delegate respondsToSelector:@selector(call:didEncounterError:reason:)])
    {
        [_delegate call:self didEncounterError:error reason:reason];
        
        [[MXSDKOptions sharedInstance].analyticsDelegate trackValue:@(reason)
                                                           category:kMXAnalyticsVoipCategory
                                                               name:kMXAnalyticsVoipNameCallError];
    }
    else
    {
        [self hangupWithReason:reason];
    }
}

- (void)expireCallInvite
{
    if (inviteExpirationTimer)
    {
        inviteExpirationTimer = nil;

        if (!_isIncoming)
        {
            // Terminate the call at the stack level we initiated
            [callStackCall end];
        }

        // Send the notif that the call expired to the app
        [self setState:MXCallStateInviteExpired reason:nil];
        
        // Set appropriate call end reason
        _endReason = MXCallEndReasonMissed;

        // And set the final state: MXCallStateEnded
        [self setState:MXCallStateEnded reason:nil];

        // The call manager can now ignore this call
        [callManager removeCall:self];
    }
}

- (void)onCallAnsweredElsewhere
{
    // Send the notif that the call has been answered from another device to the app
    [self setState:MXCallStateAnsweredElseWhere reason:nil];
    
    // Set appropriate call end reason
    _endReason = MXCallEndReasonAnsweredElseWhere;

    // And set the final state: MXCallStateEnded
    [self setState:MXCallStateEnded reason:nil];

    // The call manager can now ignore this call
    [callManager removeCall:self];
}

@end

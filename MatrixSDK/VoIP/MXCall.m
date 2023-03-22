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
#import "MatrixSDKSwiftHeader.h"

#pragma mark - Constants definitions
NSString *const kMXCallStateDidChange = @"kMXCallStateDidChange";
NSString *const kMXCallSupportsHoldingStatusDidChange = @"kMXCallSupportsHoldingStatusDidChange";
NSString *const kMXCallSupportsTransferringStatusDidChange = @"kMXCallSupportsTransferringStatusDidChange";

@interface MXCall ()
#if TARGET_OS_IPHONE
<MXiOSAudioOutputRouterDelegate>
#endif
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
    
    /**
     Operation queue to collect operations before turn server response received.
     */
    NSOperationQueue *callStackCallOperationQueue;
}

/**
 Selected answer for this call. Can be nil.
 */
@property (nonatomic, strong) MXEvent *selectedAnswer;

@property (readwrite, nonatomic) BOOL isVideoCall;
@property (nonatomic, readwrite) MXiOSAudioOutputRouter *audioOutputRouter;

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

        // PSTN calls received in the terminated app state(with the room automatically created
        // and joined server-side) will not necessarily be synced and stored locally yet.
        _room = [callManager.mxSession getOrCreateRoom: roomId];
        
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
            MXLogErrorDetails(@"[MXCall] Error: Cannot create call. [MXCallStack createCall] returned nil.", @{
                @"call_id": _callId ?: @"unknown"
            });
            [callManager.mxSession releasePreventPause];
            return nil;
        }

        callStackCall.delegate = self;

        callStackCallOperationQueue = [[NSOperationQueue alloc] init];
        callStackCallOperationQueue.qualityOfService = NSQualityOfServiceUserInteractive;
        callStackCallOperationQueue.maxConcurrentOperationCount = 1;
        callStackCallOperationQueue.underlyingQueue = dispatch_get_main_queue();
        callStackCallOperationQueue.suspended = YES;

        // Set up TURN/STUN servers if we have them
        if (callManager.turnServersReceived)
        {
            [self configureTurnOrSTUNServers];
            
            //  do not wait for turn server response for future operations
            callStackCallOperationQueue.suspended = NO;
        }
        else
        {
            //  add an observer for turn servers received notification
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(turnServersReceived:)
                                                         name:kMXCallManagerTurnServersReceived
                                                       object:nil];
        }
        
        MXLogDebug(@"[MXCall][%@] Initialized with room_id: %@, signalingRoomId: %@", _callId, roomId, callSignalingRoomId)
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
    MXLogDebug(@"[MXCall][%@] callWithVideo: %@", _callId, video ? @"YES" : @"NO");
    
    _isIncoming = NO;

    self.isVideoCall = video;

    [self setState:MXCallStateWaitLocalMedia reason:nil];
    
    [MXSDKOptions.sharedInstance.analyticsDelegate trackCallStartedWithVideo:self.isVideoCall
                                                        numberOfParticipants:self.room.summary.membersCount.joined
                                                                    incoming:self.isIncoming];

    MXWeakify(self);
    [callStackCallOperationQueue addOperationWithBlock:^{
        MXStrongifyAndReturnIfNil(self);
        
        MXWeakify(self);
        [self->callStackCall startCapturingMediaWithVideo:video success:^() {
            MXStrongifyAndReturnIfNil(self);
            
#if TARGET_OS_IPHONE
            [self.audioOutputRouter reroute];
#endif
            
            MXWeakify(self);
            [self->callStackCall createOffer:^(NSString *sdp) {
                MXStrongifyAndReturnIfNil(self);

                [self setState:MXCallStateCreateOffer reason:nil];

                MXLogDebug(@"[MXCall][%@] callWithVideo: Offer created: %@", self.callId, sdp);

                // The call invite can sent to the HS
                NSMutableDictionary *content = [@{
                    @"call_id": self.callId,
                    @"offer": @{
                            @"type": kMXCallSessionDescriptionTypeStringOffer,
                            @"sdp": sdp
                    },
                    @"version": kMXCallVersion,
                    @"lifetime": @(self->callManager.inviteLifetime),
                    @"capabilities": @{@"m.call.transferee": @(NO)},
                    @"party_id": self.partyId
                } mutableCopy];
                
                NSString *directUserId = self.room.directUserId;
                if (directUserId)
                {
                    content[@"invitee"] = directUserId;
                }
                
                MXWeakify(self);
                [self.callSignalingRoom sendEventOfType:kMXEventTypeStringCallInvite content:content threadId:nil localEcho:nil success:^(NSString *eventId) {

                    self->callInviteEventContent = [MXCallInviteEventContent modelFromJSON:content];
                    [self setState:MXCallStateInviteSent reason:nil];

                } failure:^(NSError *error) {
                    MXStrongifyAndReturnIfNil(self);
                    
                    MXLogErrorDetails(@"[MXCall] callWithVideo: ERROR: Cannot send m.call.invite event.", @{
                        @"call_id": self.callId ?: @"unknown"
                    });
                    [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
                }];

            } failure:^(NSError *error) {
                MXStrongifyAndReturnIfNil(self);
                
                MXLogErrorDetails(@"[MXCall] callWithVideo: ERROR: Cannot create offer", [self detailsForError:error]);
                [self didEncounterError:error reason:MXCallHangupReasonIceFailed];
            }];
        } failure:^(NSError *error) {
            MXStrongifyAndReturnIfNil(self);
            
            MXLogErrorDetails(@"[MXCall] callWithVideo: ERROR: Cannot start capturing media", [self detailsForError:error]);
            [self didEncounterError:error reason:MXCallHangupReasonUserMediaFailed];
        }];
    }];
}

- (void)answer
{
    MXLogDebug(@"[MXCall][%@] answer", _callId);
    
    MXWeakify(self);
    [callStackCallOperationQueue addOperationWithBlock:^{
        
        MXStrongifyAndReturnIfNil(self);
        
        // Sanity check on the call state
        // Note that e2e rooms requires several attempts of [MXCall answer] in case of unknown devices
        if (self.state == MXCallStateRinging
            || (self.callSignalingRoom.summary.isEncrypted && self.state == MXCallStateCreateAnswer))
        {
            [self setState:MXCallStateCreateAnswer reason:nil];

            MXWeakify(self);
            void(^answer)(void) = ^{
                MXStrongifyAndReturnIfNil(self);

                MXLogDebug(@"[MXCall][%@] answer: answering...", self.callId);

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

                    MXLogDebug(@"[MXCall][%@] answer - Created SDP:\n%@", self.callId, sdpAnswer);

                    // The call invite can sent to the HS
                    NSDictionary *content = @{
                                              @"call_id": self.callId,
                                              @"answer": @{
                                                      @"type": kMXCallSessionDescriptionTypeStringAnswer,
                                                      @"sdp": sdpAnswer
                                                      },
                                              @"capabilities": @{@"m.call.transferee": @(NO)},
                                              @"version": kMXCallVersion,
                                              @"party_id": self.partyId
                                              };
                    
                    MXWeakify(self);
                    
                    [self.callSignalingRoom sendEventOfType:kMXEventTypeStringCallAnswer content:content threadId:nil localEcho:nil success:^(NSString *eventId){
                        //  assume for now, this is the selected answer
                        self.selectedAnswer = [MXEvent modelFromJSON:@{
                            @"event_id": eventId,
                            @"sender": self.callSignalingRoom.mxSession.myUserId,
                            @"room_id": self.callSignalingRoom.roomId,
                            @"type": kMXEventTypeStringCallAnswer,
                            @"content": content
                        }];
                    } failure:^(NSError *error) {
                        MXStrongifyAndReturnIfNil(self);
                        
                        MXLogErrorDetails(@"[MXCall] answer: ERROR: Cannot send m.call.answer event.", @{
                            @"call_id": self.callId ?: @"unknown"
                        });
                        [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
                    }];

                } failure:^(NSError *error) {
                    MXStrongifyAndReturnIfNil(self);
                    
                    MXLogErrorDetails(@"[MXCall] answer: ERROR: Cannot create answer", [self detailsForError:error]);
                    [self didEncounterError:error reason:MXCallHangupReasonIceFailed];
                }];
            };
            
            // If the room is encrypted, we need to check that encryption is set up
            // in the room before actually answering.
            // That will allow MXCall to send ICE candidates events without encryption errors like
            // MXEncryptingErrorUnknownDeviceReason.
            if (self.callSignalingRoom.summary.isEncrypted)
            {
                MXLogDebug(@"[MXCall][%@] answer: ensuring encryption is ready to use ...", self.callId);
                
                MXWeakify(self);
                [self->callManager.mxSession.crypto ensureEncryptionInRoom:self.callSignalingRoom.roomId success:answer failure:^(NSError *error) {
                    MXStrongifyAndReturnIfNil(self);
                    
                    MXLogErrorDetails(@"[MXCall] answer: ERROR: [MXCrypto ensureEncryptionInRoom] failed", [self detailsForError:error]);
                    [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
                }];
            }
            else
            {
                answer();
            }
            
            
        }
        else
        {
            //  Since we're queueing the operations until we receive turn servers from the HS,
            //  if user answers the call too quickly (before we receive turn servers from HS), then
            //  we immediately continue on the operation queue, which causes the call state is not ringing yet,
            //  because the operations are asynchronous. On this situation we cannot really answer the call.
            //  So, retry this operation in a short future.
            MXWeakify(self);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                MXStrongifyAndReturnIfNil(self);
                if (self.state != MXCallStateEnded)
                {
                    [self answer];
                }
            });
        }
    }];
}

- (void)hangup
{
    //  hangup with the default reason
    [self hangupWithReason:MXCallHangupReasonUserHangup];
}

- (void)hangupWithReason:(MXCallHangupReason)reason
{
    [self hangupWithReason:reason
                    signal:YES];
}

- (void)hangupWithReason:(MXCallHangupReason)reason
                  signal:(BOOL)signal
{
    MXLogDebug(@"[MXCall][%@] hangupWithReason: %@, signal: %@", _callId, [MXTools callHangupReasonString:reason], signal ? @"YES" : @"NO");
    
    if (self.state == MXCallStateRinging && [callInviteEventContent.version isEqualToString:kMXCallVersion])
    {
        // Create the reject event for new call invites
        NSDictionary *content = @{
                                  @"call_id": _callId,
                                  @"version": kMXCallVersion,
                                  @"party_id": self.partyId
                                  };
        
        void(^terminateBlock)(void) = ^{
            //  terminate with a fake reject event
            MXEvent *fakeEvent = [MXEvent modelFromJSON:@{
                @"type": kMXEventTypeStringCallReject,
                @"content": content
            }];
            fakeEvent.sender = self->callManager.mxSession.myUserId;
            [self terminateWithReason:fakeEvent];
        };
        
        if (signal)
        {
            // Send the reject event
            MXWeakify(self);
            [_callSignalingRoom sendEventOfType:kMXEventTypeStringCallReject content:content threadId:nil localEcho:nil success:^(NSString *eventId) {
                terminateBlock();
            } failure:^(NSError *error) {
                MXStrongifyAndReturnIfNil(self);
                
                MXLogErrorDetails(@"[MXCall] hangup: ERROR: Cannot send m.call.reject event.", @{
                    @"call_id": self.callId ?: @"unknown"
                });
                [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
            }];
        }
        else
        {
            terminateBlock();
        }
        return;
    }
    
    if (self.state != MXCallStateEnded)
    {
        // Create the hangup event
        NSDictionary *content = @{
                                  @"call_id": _callId,
                                  @"version": kMXCallVersion,
                                  @"party_id": self.partyId,
                                  @"reason": [MXTools callHangupReasonString:reason]
                                  };
        
        void(^terminateBlock)(void) = ^{
            //  terminate with a fake hangup event
            MXEvent *fakeEvent = [MXEvent modelFromJSON:@{
                @"type": kMXEventTypeStringCallHangup,
                @"content": content
            }];
            fakeEvent.sender = self->callManager.mxSession.myUserId;
            [self terminateWithReason:fakeEvent];
        };
        
        if (signal)
        {
            //  Send the hangup event
            MXWeakify(self);
            [_callSignalingRoom sendEventOfType:kMXEventTypeStringCallHangup content:content threadId:nil localEcho:nil success:^(NSString *eventId) {
                [MXSDKOptions.sharedInstance.analyticsDelegate trackCallEndedWithDuration:self.duration
                                                                                    video:self.isVideoCall
                                                                     numberOfParticipants:self.room.summary.membersCount.joined
                                                                                 incoming:self.isIncoming];
                
                terminateBlock();
            } failure:^(NSError *error) {
                MXStrongifyAndReturnIfNil(self);
                
                MXLogErrorDetails(@"[MXCall] hangupWithReason: ERROR: Cannot send m.call.hangup event.", @{
                    @"call_id": self.callId ?: @"unknown"
                });
                [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
            }];
        }
        else
        {
            terminateBlock();
        }
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
    MXLogDebug(@"[MXCall][%@] hold: %@", self.callId, hold ? @"YES" : @"NO");
    
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
    [callStackCallOperationQueue addOperationWithBlock:^{
        MXStrongifyAndReturnIfNil(self);
        
        MXWeakify(self);
        [self->callStackCall hold:hold success:^(NSString * _Nonnull sdp) {
            MXStrongifyAndReturnIfNil(self);
            
            MXLogDebug(@"[MXCall][%@] offer created: %@", self.callId, sdp);

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
            
            MXWeakify(self);
            [self.callSignalingRoom sendEventOfType:kMXEventTypeStringCallNegotiate content:content threadId:nil localEcho:nil success:^(NSString *eventId) {

                if (hold)
                {
                    [self setState:MXCallStateOnHold reason:nil];
                }
                else
                {
                    [self setState:MXCallStateConnected reason:nil];
                }

            } failure:^(NSError *error) {
                MXStrongifyAndReturnIfNil(self);
                
                MXLogErrorDetails(@"[MXCall] hold: ERROR: Cannot send m.call.negotiate event.", @{
                    @"call_id": self.callId ?: @"unknown"
                });
                [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
            }];
            
        } failure:^(NSError * _Nonnull error) {
            MXStrongifyAndReturnIfNil(self);
            
            MXLogErrorDetails(@"[MXCall] hold: ERROR: Cannot create offer", [self detailsForError:error]);
            [self didEncounterError:error reason:MXCallHangupReasonIceFailed];
        }];
    }];
}

- (BOOL)isOnHold
{
    return _state == MXCallStateOnHold || _state == MXCallStateRemotelyOnHold;
}

#pragma mark - Transfer

- (BOOL)supportsTransferring
{
    if (self.isIncoming)
    {
        return callInviteEventContent.capabilities.transferee;
    }
    else if (_selectedAnswer)
    {
        MXCallAnswerEventContent *content = [MXCallAnswerEventContent modelFromJSON:_selectedAnswer.content];
        return content.capabilities.transferee;
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
    MXLogDebug(@"[MXCall][%@] transferToRoom: %@, user: %@, createCall: %@, awaitCall: %@", _callId, targetRoomId, targetUser.userId, createCallId, awaitCallId)
    
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
    
    MXWeakify(self);
    [self.callSignalingRoom sendEventOfType:kMXEventTypeStringCallReplaces
                                    content:content.JSONDictionary
                                   threadId:nil
                                  localEcho:nil
                                    success:^(NSString *eventId) {
        MXStrongifyAndReturnIfNil(self);
        
        [self hangupWithReason:MXCallHangupReasonUserHangup signal:NO];
        if (success)
        {
            success(eventId);
        }
    }
                                    failure:^(NSError *error) {
        MXStrongifyAndReturnIfNil(self);
        
        MXLogErrorDetails(@"[MXCall] transferToRoom: ERROR: Cannot send m.call.replaces event", @{
            @"call_id": self.callId ?: @"unknown"
        });
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
{
    return [callStackCall sendDTMF:tones];
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
    MXLogDebug(@"[MXCall][%@] setState: Old: %@. New: %@", _callId, @(_state), @(state));

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
        
        [MXSDKOptions.sharedInstance.analyticsDelegate trackCallEndedWithDuration:self.duration
                                                                            video:self.isVideoCall
                                                             numberOfParticipants:self.room.summary.membersCount.joined
                                                                         incoming:self.isIncoming];
        
        // Terminate the call at the stack level
        [callStackCall end];
    }
    else if (MXCallStateInviteSent == state)
    {
        // Start the life expiration timer for the sent invitation
        [self startInviteExpirationTimer];
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
        
        MXWeakify(self);
        [callStackCallOperationQueue addOperationWithBlock:^{
            MXStrongifyAndReturnIfNil(self);
            
            self->callStackCall.selfVideoView = selfVideoView;
        }];
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
        
        MXWeakify(self);
        [callStackCallOperationQueue addOperationWithBlock:^{
            MXStrongifyAndReturnIfNil(self);
            
            self->callStackCall.remoteVideoView = remoteVideoView;
        }];
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

- (void)setIsVideoCall:(BOOL)isVideoCall
{
    _isVideoCall = isVideoCall;
    [self configureAudioOutputRouter];
}

- (MXiOSAudioOutputRouter *)audioOutputRouter
{
    if (_audioOutputRouter == nil)
    {
        [self configureAudioOutputRouter];
    }
    return _audioOutputRouter;
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

- (void)setConsulting:(BOOL)consulting
{
    if (_consulting != consulting)
    {
        _consulting = consulting;
        
        if ([_delegate respondsToSelector:@selector(callConsultingStatusDidChange:)])
        {
            [_delegate callConsultingStatusDidChange:self];
        }
    }
}

- (void)setAssertedIdentity:(MXAssertedIdentityModel *)assertedIdentity
{
    if (![_assertedIdentity isEqual:assertedIdentity])
    {
        _assertedIdentity = assertedIdentity;
        
        if (self.isEstablished && _state != MXCallStateEnded)
        {
            //  reset call connected date
            callConnectedDate = [NSDate date];
        }
        
        if ([_delegate respondsToSelector:@selector(callAssertedIdentityDidChange:)])
        {
            [_delegate callAssertedIdentityDidChange:self];
        }
    }
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
        MXLogDebug(@"MXCall][%@] onICECandidate: Send %tu candidates", _callId, localICECandidates.count);

        NSDictionary *content = @{
                                  @"version": kMXCallVersion,
                                  @"call_id": _callId,
                                  @"candidates": localICECandidates,
                                  @"party_id": self.partyId
                                  };

        MXWeakify(self);
        [_callSignalingRoom sendEventOfType:kMXEventTypeStringCallCandidates content:content threadId:nil localEcho:nil success:nil failure:^(NSError *error) {
            MXStrongifyAndReturnIfNil(self);
            
            MXLogErrorDetails(@"[MXCall] onICECandidate: Warning: Cannot send m.call.candidates event", @{
                @"call_id": self.callId ?: @"unknown"
            });
            [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
        }];

        [localICECandidates removeAllObjects];
    }
}

- (void)callStackCallDidRemotelyHold:(id<MXCallStackCall>)callStackCall
{
    MXLogDebug(@"[MXCall][%@] callStackCallDidRemotelyHold", _callId);
    
    if (self.state == MXCallStateConnected)
    {
        [self setState:MXCallStateRemotelyOnHold reason:nil];
    }
}

- (void)callStackCall:(id<MXCallStackCall>)callStackCall onError:(NSError *)error
{
    MXLogErrorDetails(@"[MXCall] callStackCall didEncounterError", [self detailsForError:error]);
    
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
    MXLogDebug(@"[MXCall][%@] callStackCallDidConnect", _callId);
    
    if (self.state == MXCallStateConnecting || self.state == MXCallStateRemotelyOnHold)
    {
        [self setState:MXCallStateConnected reason:nil];
    }
}

#pragma mark - Event Handlers

- (void)handleCallInvite:(MXEvent *)event
{
    MXLogDebug(@"[MXCall][%@] handleCallInvite", _callId)
    
    callInviteEventContent = [MXCallInviteEventContent modelFromJSON:event.content];
    
    if ([self isMyEvent:event])
    {
        return;
    }

    // Incoming call

    if (_state >= MXCallStateWaitLocalMedia)
    {
        //  already processed invite, do nothing
        return;
    }

    _callId = callInviteEventContent.callId;
    _callerId = event.sender;
    _callerName = [callManager.mxSession userWithUserId:_callerId].displayname;
    MXRoom *signalingRoom = [callManager.mxSession roomWithRoomId:event.roomId];
    //  for virtual signaling rooms, use the real room's info instead
    if (signalingRoom.accountData.virtualRoomInfo.isVirtual)
    {
        MXRoom *nativeRoom = [callManager.mxSession roomWithRoomId:signalingRoom.accountData.virtualRoomInfo.nativeRoomId];
        if (nativeRoom.isDirect)
        {
            _callerId = nativeRoom.directUserId;
            _callerName = [callManager.mxSession userWithUserId:_callerId].displayname;
        }
        else
        {
            _callerName = nativeRoom.summary.displayName;
        }
    }
    calleeId = callManager.mxSession.myUserId;
    _isIncoming = YES;

    // Store if it is voice or video call
    self.isVideoCall = callInviteEventContent.isVideoCall;
    
    [MXSDKOptions.sharedInstance.analyticsDelegate trackCallStartedWithVideo:self.isVideoCall
                                                        numberOfParticipants:self.room.summary.membersCount.joined
                                                                    incoming:self.isIncoming];

    [self setState:MXCallStateWaitLocalMedia reason:nil];
    
    MXWeakify(self);
    [callStackCallOperationQueue addOperationWithBlock:^{
        MXStrongifyAndReturnIfNil(self);
        
        MXLogDebug(@"[MXCall][%@] start processing invite block", self.callId)
        
        MXWeakify(self);
        [self->callStackCall startCapturingMediaWithVideo:self.isVideoCall success:^{
            MXStrongifyAndReturnIfNil(self);
            
            MXLogDebug(@"[MXCall][%@] capturing media", self.callId)
            
#if TARGET_OS_IPHONE
            [self.audioOutputRouter reroute];
#endif
            
            [self->callStackCall handleOffer:self->callInviteEventContent.offer.sdp
                                     success:^{
                MXStrongifyAndReturnIfNil(self);
                
                MXLogDebug(@"[MXCall][%@] successfully handled offer", self.callId)
                // Check whether the call has not been ended.
                if (self.state != MXCallStateEnded)
                {
                    [self setState:MXCallStateRinging reason:event];
                }
            }
                                     failure:^(NSError * _Nonnull error) {
                MXStrongifyAndReturnIfNil(self);
                
                MXLogErrorDetails(@"[MXCall] handleCallInvite: ERROR: Couldn't handle offer", [self detailsForError:error]);
                [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
            }];
            
            
        } failure:^(NSError *error) {
            MXStrongifyAndReturnIfNil(self);
            
            MXLogErrorDetails(@"[MXCall] handleCallInvite: startCapturingMediaWithVideo : ERROR: Couldn't start capturing", [self detailsForError:error]);
            [self didEncounterError:error reason:MXCallHangupReasonUserMediaFailed];
        }];

        // Start an expiration timer
        [self startInviteExpirationTimer];
    }];
}

- (void)startInviteExpirationTimer {
    if (inviteExpirationTimer)
    {
        return;
    }
    
    // Start expiration timer
    inviteExpirationTimer = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:callInviteEventContent.lifetime / 1000]
                                                     interval:0
                                                       target:self
                                                     selector:@selector(expireCallInvite)
                                                     userInfo:nil
                                                      repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:inviteExpirationTimer forMode:NSDefaultRunLoopMode];
}

- (void)invalidateInviteExpirationTimer {
    if (inviteExpirationTimer)
    {
        [inviteExpirationTimer invalidate];
        inviteExpirationTimer = nil;
    }
}

- (void)handleCallAnswer:(MXEvent *)event
{
    MXLogDebug(@"[MXCall][%@] handleCallAnswer", _callId)
    
    if ([self isMyEvent:event])
    {
        return;
    }
    
    if (_state == MXCallStateEnded) {
        // this call is already ended
        MXLogDebug(@"[MXCall][%@] handleCallAnswer: this call is already ended", _callId);
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
        [self invalidateInviteExpirationTimer];
        
        //  mark this as the selected one
        self.selectedAnswer = event;
        
        void(^continueBlock)(void) = ^{
            // Let's the stack finalise the connection
            [self setState:MXCallStateConnecting reason:event];
            
            MXWeakify(self);
            [self->callStackCall handleAnswer:content.answer.sdp
                                success:^{}
                                failure:^(NSError *error) {
                MXStrongifyAndReturnIfNil(self);
                
                MXLogErrorDetails(@"[MXCall] handleCallAnswer: ERROR: Cannot send handle answer", [self detailsForError:error]);
                self.selectedAnswer = nil;
                [self didEncounterError:error reason:MXCallHangupReasonIceFailed];
            }];
        };
        
        //  The content doesn't have to have a partyId, as `content.version` fallbacks to `kMXCallVersion` if not provided.
        if ([content.version isEqualToString:kMXCallVersion] && content.partyId)
        {
            NSDictionary *selectAnswerContent = @{
                @"call_id": self.callId,
                @"version": kMXCallVersion,
                @"party_id": self.partyId,
                @"selected_party_id": content.partyId
            };
            
            MXWeakify(self);
            [self.callSignalingRoom sendEventOfType:kMXEventTypeStringCallSelectAnswer
                                            content:selectAnswerContent
                                           threadId:nil
                                          localEcho:nil
                                            success:^(NSString *eventId) {
                
                continueBlock();
                
            } failure:^(NSError *error) {
                MXStrongifyAndReturnIfNil(self);
                
                MXLogErrorDetails(@"[MXCall] handleCallAnswer: ERROR: Cannot send m.call.select_answer event", [self detailsForError:error]);
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
    MXLogDebug(@"[MXCall][%@] handleCallSelectAnswer", _callId)
    
    if ([self isMyEvent:event])
    {
        return;
    }
    
    if (_state == MXCallStateEnded) {
        // this call is already ended
        MXLogDebug(@"[MXCall][%@] handleCallAnswer: this call is already ended", _callId);
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
    MXLogDebug(@"[MXCall][%@] handleCallHangup", _callId)
    
    if (_state != MXCallStateEnded)
    {
        [self terminateWithReason:event];
    }
}

- (void)handleCallCandidates:(MXEvent *)event
{
    MXLogDebug(@"[MXCall][%@] handleCallCandidates", _callId)
    
    if ([self isMyEvent:event])
    {
        return;
    }

    MXWeakify(self);
    [callStackCallOperationQueue addOperationWithBlock:^{
        MXStrongifyAndReturnIfNil(self);
        
        MXCallCandidatesEventContent *content = [MXCallCandidatesEventContent modelFromJSON:event.content];

        MXLogDebug(@"[MXCall][%@] handleCallCandidates: %@", self.callId, content.candidates);
        for (MXCallCandidate *canditate in content.candidates)
        {
            [self->callStackCall handleRemoteCandidate:canditate.JSONDictionary];
        }
    }];
}

- (void)handleCallReject:(MXEvent *)event
{
    MXLogDebug(@"[MXCall][%@] handleCallReject", _callId)
    
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
        [self invalidateInviteExpirationTimer];
        
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
            
            MXWeakify(self);
            [self.callSignalingRoom sendEventOfType:kMXEventTypeStringCallSelectAnswer
                                            content:selectAnswerContent
                                           threadId:nil
                                          localEcho:nil
                                            success:^(NSString *eventId) {
                
                MXStrongifyAndReturnIfNil(self);
                
                [self terminateWithReason:event];
                
            } failure:^(NSError *error) {
                MXStrongifyAndReturnIfNil(self);
                
                MXLogErrorDetails(@"[MXCall] handleCallReject: ERROR: Cannot send m.call.select_answer event", [self detailsForError:error]);
                self.selectedAnswer = nil;
                [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
            }];
        }
    }
    else
    {
        [self onCallDeclinedElsewhere];
    }
}

- (void)handleCallNegotiate:(MXEvent *)event
{
    MXLogDebug(@"[MXCall][%@] handleCallNegotiate", _callId)
    
    if ([self isMyEvent:event])
    {
        return;
    }
    
    if (![self canHandleNegotiationEvent:event])
    {
        return;
    }
    
    MXWeakify(self);
    [callStackCallOperationQueue addOperationWithBlock:^{
        MXStrongifyAndReturnIfNil(self);
        
        MXCallNegotiateEventContent *content = [MXCallNegotiateEventContent modelFromJSON:event.content];
        
        if (content.sessionDescription.type == MXCallSessionDescriptionTypeOffer)
        {
            // Store if it is voice or video call
            self.isVideoCall = content.isVideoCall;

            MXWeakify(self);
            [self->callStackCall handleOffer:content.sessionDescription.sdp
                                     success:^{
                MXStrongifyAndReturnIfNil(self);
                
                //  TODO: Get offer type from handleOffer and decide auto-accept it or not
                //  auto-accept negotiations for now
                MXWeakify(self);
                [self->callStackCall createAnswer:^(NSString * _Nonnull sdpAnswer) {
                    MXStrongifyAndReturnIfNil(self);
                    
                    MXLogDebug(@"[MXCall][%@] handleCallNegotiate: answer negotiation - Created SDP:\n%@", self.callId, sdpAnswer);
                    
                    NSDictionary *content = @{
                        @"call_id": self.callId,
                        @"description": @{
                                @"type": kMXCallSessionDescriptionTypeStringAnswer,
                                @"sdp": sdpAnswer
                        },
                        @"version": kMXCallVersion,
                        @"party_id": self.partyId
                    };
                    
                    MXWeakify(self);
                    [self.callSignalingRoom sendEventOfType:kMXEventTypeStringCallNegotiate content:content threadId:nil localEcho:nil success:nil failure:^(NSError *error) {
                        MXStrongifyAndReturnIfNil(self);
                        
                        MXLogErrorDetails(@"[MXCall] handleCallNegotiate: negotiate answer: ERROR: Cannot send m.call.negotiate event.", @{
                            @"call_id": self.callId ?: @"unknown"
                        });
                        [self didEncounterError:error reason:MXCallHangupReasonUnknownError];
                    }];
                } failure:^(NSError * _Nonnull error) {
                    MXStrongifyAndReturnIfNil(self);
                    
                    MXLogErrorDetails(@"[MXCall] handleCallNegotiate: negotiate answer: ERROR: Cannot create negotiate answer", [self detailsForError:error]);
                    [self didEncounterError:error reason:MXCallHangupReasonIceFailed];
                }];
            }
                                     failure:^(NSError * _Nonnull error) {
                MXStrongifyAndReturnIfNil(self);
                
                MXLogErrorDetails(@"[MXCall] handleCallNegotiate: ERROR: Couldn't handle negotiate offer", [self detailsForError:error]);
                [self didEncounterError:error reason:MXCallHangupReasonIceFailed];
            }];
        }
        else if (content.sessionDescription.type == MXCallSessionDescriptionTypeAnswer)
        {
            MXWeakify(self);
            [self->callStackCall handleAnswer:content.sessionDescription.sdp
                                success:^{}
                                failure:^(NSError *error) {
                MXStrongifyAndReturnIfNil(self);
                
                MXLogErrorDetails(@"[MXCall] handleCallNegotiate: ERROR: Cannot send handle negotiate answer", [self detailsForError:error]);
                [self didEncounterError:error reason:MXCallHangupReasonIceFailed];
            }];
        }
    }];
}

- (void)handleCallReplaces:(MXEvent *)event
{
    MXLogDebug(@"[MXCall][%@] handleCallReplaces", _callId)
}

- (void)handleCallRejectReplacement:(MXEvent *)event
{
    MXLogDebug(@"[MXCall][%@] handleCallRejectReplacement", _callId)
}

#if TARGET_OS_IPHONE
#pragma mark - MXiOSAudioOutputRouterDelegate

- (void)audioOutputRouterWithDidUpdateRoute:(MXiOSAudioOutputRouter *)router
{
    if ([_delegate respondsToSelector:@selector(callAudioOutputRouteTypeDidChange:)])
    {
        [_delegate callAudioOutputRouteTypeDidChange:self];
    }
}

- (void)audioOutputRouterWithDidUpdateAvailableRouteTypes:(MXiOSAudioOutputRouter *)router
{
    if ([_delegate respondsToSelector:@selector(callAvailableAudioOutputsDidChange:)])
    {
        [_delegate callAvailableAudioOutputsDidChange:self];
    }
}
#endif

#pragma mark - Private methods

- (void)configureAudioOutputRouter
{
#if TARGET_OS_IPHONE
    _audioOutputRouter = [[MXiOSAudioOutputRouter alloc] initForCall:self];
    _audioOutputRouter.delegate = self;
#endif
}

- (void)turnServersReceived:(NSNotification *)notification
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kMXCallManagerTurnServersReceived object:nil];
    
    [self configureTurnOrSTUNServers];
    
    //  continue on operations waiting on the queue
    callStackCallOperationQueue.suspended = NO;
}

- (void)configureTurnOrSTUNServers
{
    // Set up TURN/STUN servers
    if (callManager.turnServers)
    {
        [callStackCall addTURNServerUris:callManager.turnServers.uris
                            withUsername:callManager.turnServers.username
                                password:callManager.turnServers.password];
    }
    else if (callManager.fallbackSTUNServer)
    {
        MXLogDebug(@"[MXCall][%@] No TURN server: using fallback STUN server: %@", _callId, callManager.fallbackSTUNServer);
        [callStackCall addTURNServerUris:@[callManager.fallbackSTUNServer] withUsername:nil password:nil];
    }
    else if (!callManager.turnServers && !callManager.fallbackSTUNServer)
    {
        MXLogDebug(@"[MXCall][%@] No TURN server and no fallback STUN server", _callId);

        // Setup the call with no STUN server
        [callStackCall addTURNServerUris:nil withUsername:nil password:nil];
    }
}

- (BOOL)canHandleNegotiationEvent:(MXEvent *)event
{
    BOOL result = NO;
    if (_isIncoming)
    {
        MXLogDebug(@"[MXCall][%@] canHandleNegotiationEvent: YES", _callId)
        return YES;
    }
    
    //  outgoing call, check the event coming from the same user with the selected answer
    if (_selectedAnswer && [_selectedAnswer.sender isEqualToString:event.sender])
    {
        MXCallEventContent *selectedAnswerContent = [MXCallEventContent modelFromJSON:_selectedAnswer.content];
        MXCallNegotiateEventContent *content = [MXCallNegotiateEventContent modelFromJSON:event.content];
        
        //  return if user-id and party-id matches
        result = [selectedAnswerContent.partyId isEqualToString:content.partyId];
    }
    
    MXLogDebug(@"[MXCall][%@] canHandleNegotiationEvent: %@", _callId, result ? @"YES" : @"NO")
    return result;
}

- (BOOL)isMyEvent:(MXEvent *)event
{
    BOOL result = NO;
    if ([event.sender isEqualToString:_callSignalingRoom.mxSession.myUserId])
    {
        MXCallEventContent *content = [MXCallEventContent modelFromJSON:event.content];
        result = [content.partyId isEqualToString:_callSignalingRoom.mxSession.myDeviceId];
    }
    MXLogDebug(@"[MXCall][%@] isMyEvent: %@", _callId, result ? @"YES" : @"NO")
    return result;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MXCall: %p> id: %@ - isVideoCall: %@ - isIncoming: %@ - state: %@", self, _callId, @(_isVideoCall), @(_isIncoming), @(_state)];
}

- (void)terminateWithReason:(MXEvent *)event
{
    [self invalidateInviteExpirationTimer];

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
                    case MXCallHangupReasonUserBusy:
                        _endReason = MXCallEndReasonBusy;
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
    
    MXLogDebug(@"[MXCall][%@] terminateWithReason: %@, endReason: %ld", _callId, event, (long)_endReason);

    [self setState:MXCallStateEnded reason:event];
}

- (void)didEncounterError:(NSError *)error reason:(MXCallHangupReason)reason
{
    if ([_delegate respondsToSelector:@selector(call:didEncounterError:reason:)])
    {
        [_delegate call:self didEncounterError:error reason:reason];
        [MXSDKOptions.sharedInstance.analyticsDelegate trackCallErrorWithReason:reason
                                                                          video:self.isVideoCall
                                                           numberOfParticipants:self.room.summary.membersCount.joined
                                                                       incoming:self.isIncoming];
    }
    else
    {
        [self hangupWithReason:reason];
    }
}

- (void)expireCallInvite
{
    MXLogDebug(@"[MXCall][%@] expireCallInvite", _callId)
    
    if (inviteExpirationTimer)
    {
        inviteExpirationTimer = nil;

        if (!_isIncoming)
        {
            // Terminate the call at the stack level we initiated
            [callStackCall end];
        }

        // If the call is not aleady ended
        if (_state != MXCallStateEnded) {
            // Send the notif that the call expired to the app
            [self setState:MXCallStateInviteExpired reason:nil];
            
            // Set appropriate call end reason
            _endReason = MXCallEndReasonMissed;
            
            // And set the final state: MXCallStateEnded
            [self setState:MXCallStateEnded reason:nil];
        }

        // The call manager can now ignore this call
        [callManager removeCall:self];
    }
}

- (void)onCallAnsweredElsewhere
{
    MXLogDebug(@"[MXCall][%@] onCallAnsweredElsewhere", _callId)
    
    // The call has been accepted elsewhere
    [self invalidateInviteExpirationTimer];
    
    // Send the notif that the call has been answered from another device to the app
    [self setState:MXCallStateAnsweredElseWhere reason:nil];
    
    // Set appropriate call end reason
    _endReason = MXCallEndReasonAnsweredElseWhere;

    // And set the final state: MXCallStateEnded
    [self setState:MXCallStateEnded reason:nil];

    // The call manager can now ignore this call
    [callManager removeCall:self];
}

- (void)onCallDeclinedElsewhere
{
    MXLogDebug(@"[MXCall][%@] onCallDeclinedElsewhere", _callId)
    
    // The call has been declined from another device
    [self invalidateInviteExpirationTimer];
    
    // Send the notif that the call has been declined from another device to the app
    [self setState:MXCallStateAnsweredElseWhere reason:nil];
    
    // Set appropriate call end reason
    _endReason = MXCallEndReasonHangupElsewhere;

    // And set the final state: MXCallStateEnded
    [self setState:MXCallStateEnded reason:nil];

    // The call manager can now ignore this call
    [callManager removeCall:self];
}

-(NSDictionary *)detailsForError:(NSError *)error
{
    return @{
        @"call_id": self.callId ?: @"unknown",
        @"error": error ?: @"unknown"
    };
}

@end

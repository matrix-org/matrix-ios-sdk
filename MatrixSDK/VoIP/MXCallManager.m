/*
 Copyright 2015 OpenMarket Ltd
 Copyright 2018 New Vector Ltd

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

#import "MXCall.h"
#import "MXCallKitAdapter.h"
#import "MXCallStack.h"
#import "MXJSONModels.h"
#import "MXRoom.h"
#import "MXSession.h"
#import "MXTools.h"

#import "MXCallInviteEventContent.h"
#import "MXCallAnswerEventContent.h"
#import "MXCallSelectAnswerEventContent.h"
#import "MXCallHangupEventContent.h"
#import "MXCallCandidatesEventContent.h"
#import "MXCallRejectEventContent.h"
#import "MXCallNegotiateEventContent.h"
#import "MXCallReplacesEventContent.h"
#import "MXCallRejectReplacementEventContent.h"
#import "MXUserModel.h"

#import "MXThirdPartyProtocol.h"
#import "MXThirdpartyProtocolsResponse.h"
#import "MXThirdPartyUsersResponse.h"
#import "MXThirdPartyUserInstance.h"

#pragma mark - Constants definitions
NSString *const kMXCallManagerNewCall                       = @"kMXCallManagerNewCall";
NSString *const kMXCallManagerConferenceStarted             = @"kMXCallManagerConferenceStarted";
NSString *const kMXCallManagerConferenceFinished            = @"kMXCallManagerConferenceFinished";
NSString *const kMXCallManagerPSTNSupportUpdated            = @"kMXCallManagerPSTNSupportUpdated";
NSString *const kMXCallManagerVirtualRoomsSupportUpdated    = @"kMXCallManagerVirtualRoomsSupportUpdated";
NSString *const kMXCallManagerTurnServersReceived           = @"kMXCallManagerTurnServersReceived";

// TODO: Replace usages of this with `kMXProtocolPSTN` when MSC completed
NSString *const kMXProtocolVectorPSTN = @"im.vector.protocol.pstn";
NSString *const kMXProtocolPSTN = @"m.protocol.pstn";

NSString *const kMXProtocolVectorSipNative = @"im.vector.protocol.sip_native";
NSString *const kMXProtocolVectorSipVirtual = @"im.vector.protocol.sip_virtual";

NSTimeInterval const kMXCallDirectRoomJoinTimeout = 30;


@interface MXCallManager ()
{
    /**
     Calls being handled.
     */
    NSMutableArray<MXCall *> *calls;

    /**
     Listener to Matrix call-related events.
     */
    id callEventsListener;

    /**
     Timer to periodically refresh the TURN server config.
     */
    NSTimer *refreshTURNServerTimer;
    
    /**
     Observer for changes of MXSession's state
     */
    id sessionStateObserver;
}

@property (nonatomic, copy) MXThirdPartyProtocol *pstnProtocol;
@property (nonatomic, assign, readwrite) BOOL supportsPSTN;
@property (nonatomic, nullable, readwrite) MXTurnServerResponse *turnServers;
@property (nonatomic, readwrite) BOOL turnServersReceived;
@property (nonatomic, assign, readwrite) BOOL virtualRoomsSupported;

@end


@implementation MXCallManager

- (instancetype)initWithMatrixSession:(MXSession *)mxSession andCallStack:(id<MXCallStack>)callstack
{
    self = [super init];
    if (self)
    {
        _mxSession = mxSession;
        calls = [NSMutableArray array];
        _inviteLifetime = 30000;
        _negotiateLifetime = 30000;
        _transferLifetime = 30000;

        _callStack = callstack;
        
        // Listen to call events
        callEventsListener = [mxSession listenToEventsOfTypes:@[
                                                                kMXEventTypeStringCallInvite,
                                                                kMXEventTypeStringCallCandidates,
                                                                kMXEventTypeStringCallAnswer,
                                                                kMXEventTypeStringCallSelectAnswer,
                                                                kMXEventTypeStringCallHangup,
                                                                kMXEventTypeStringCallReject,
                                                                kMXEventTypeStringCallNegotiate,
                                                                kMXEventTypeStringCallReplaces,
                                                                kMXEventTypeStringCallRejectReplacement,
                                                                kMXEventTypeStringCallAssertedIdentity,
                                                                kMXEventTypeStringCallAssertedIdentityUnstable,
                                                                kMXEventTypeStringRoomMember
                                                                ]
                                                      onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

            if (MXTimelineDirectionForwards == direction)
            {
                [self handleCallEvent:event];
            }
        }];

        // Listen to call state changes
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleCallStateDidChangeNotification:)
                                                     name:kMXCallStateDidChange
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleCallSupportHoldingStatusDidChange:)
                                                     name:kMXCallSupportsHoldingStatusDidChange
                                                   object:nil];
        
        [self refreshTURNServer];
        [self checkThirdPartyProtocols];
    }
    return self;
}

- (void)dealloc
{
    [self unregisterFromNotifications];
}

- (void)close
{
    [_mxSession removeListener:callEventsListener];
    callEventsListener = nil;

    // Hang up all calls
    for (MXCall *call in calls)
    {
        [call hangupWithReason:MXCallHangupReasonUserHangup signal:NO];
    }
    [calls removeAllObjects];
    calls = nil;

    // Do not refresh TURN servers config anymore
    [refreshTURNServerTimer invalidate];
    refreshTURNServerTimer = nil;
    
    // Unregister from any possible notifications
    [self unregisterFromNotifications];
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
        if ([call.room.roomId isEqualToString:roomId])
        {
            theCall = call;
            break;
        }
    }
    return theCall;
}

- (void)placeCallInRoom:(NSString *)roomId withVideo:(BOOL)video
                success:(void (^)(MXCall *call))success
                failure:(void (^)(NSError * _Nullable error))failure
{
    // If consumers of our API decide to use SiriKit or CallKit, they will face with application:continueUserActivity:restorationHandler:
    // and since the state of MXSession can be different from MXSessionStateRunning for the moment when this method will be executing
    // we must track session's state to become MXSessionStateRunning for performing outgoing call
    if (_mxSession.state != MXSessionStateRunning)
    {
        MXWeakify(self);
        __weak NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        sessionStateObserver = [center addObserverForName:kMXSessionStateDidChangeNotification
                                                   object:_mxSession
                                                    queue:[NSOperationQueue mainQueue]
                                               usingBlock:^(NSNotification * _Nonnull note) {
                                                   MXStrongifyAndReturnIfNil(self);
                                                   
                                                   if (self.mxSession.state == MXSessionStateRunning)
                                                   {
                                                       [self placeCallInRoom:roomId
                                                                         withVideo:video
                                                                           success:success
                                                                           failure:failure];
                                                       
                                                       [center removeObserver:self->sessionStateObserver];
                                                       self->sessionStateObserver = nil;
                                                   }
                                               }];
        return;
    }
    
    MXRoom *room = [_mxSession roomWithRoomId:roomId];

    if (room && 1 < room.summary.membersCount.joined)
    {
        if (2 == room.summary.membersCount.joined)
        {
            void (^initCall)(NSString *) = ^(NSString *callSignalingRoomId){
                // Do a peer to peer, one to one call
                MXLogDebug(@"[MXCallManager] placeCallInRoom: Creating call in %@", callSignalingRoomId);
                MXCall *call = [[MXCall alloc] initWithRoomId:roomId callSignalingRoomId:callSignalingRoomId andCallManager:self];
                if (call)
                {
                    [self->calls addObject:call];

                    [call callWithVideo:video];

                    // Broadcast the new outgoing call
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMXCallManagerNewCall object:call userInfo:nil];

                    if (success)
                    {
                        success(call);
                    }
                }
                else
                {
                    if (failure)
                    {
                        failure(nil);
                    }
                }
            };
            
            if (self.isVirtualRoomsSupported)
            {
                NSString *directUserId = room.directUserId;
                
                if (directUserId)
                {
                    [self getVirtualUserFrom:directUserId success:^(MXThirdPartyUserInstance * _Nonnull user) {
                        [self directCallableRoomWithVirtualUser:user.userId
                                                   nativeRoomId:roomId
                                                        timeout:kMXCallDirectRoomJoinTimeout
                                                     completion:^(MXRoom * _Nullable roomWithVirtualUser, NSError * _Nullable error) {
                            if (error)
                            {
                                if (failure)
                                {
                                    failure(error);
                                }
                            }
                            else
                            {
                                initCall(roomWithVirtualUser.roomId);
                            }
                        }];
                    } failure:^(NSError * _Nullable error) {
                        if (error)
                        {
                            //  there is a real error
                            if (failure)
                            {
                                failure(error);
                            }
                        }
                        else
                        {
                            //  no virtual user, continue with normal flow
                            initCall(roomId);
                        }
                    }];
                }
                else
                {
                    initCall(roomId);
                }
            }
            else
            {
                initCall(roomId);
            }
        }
        else
        {
            // Use the conference server bot to manage the conf call
            // There are 2 steps:
            //    - invite the conference user (the bot) into the room
            //    - set up a separated private room with the conference user to manage
            //      the conf call in 'room'
            MXWeakify(self);
            [self inviteConferenceUserToRoom:room success:^{
                MXStrongifyAndReturnIfNil(self);

                MXWeakify(self);
                [self conferenceUserRoomForRoom:roomId success:^(MXRoom *conferenceUserRoom) {
                    MXStrongifyAndReturnIfNil(self);

                    // The call can now be created
                    MXLogDebug(@"[MXCallManager] placeCallInRoom: Creating conference call in %@", conferenceUserRoom.roomId);
                    MXCall *call = [[MXCall alloc] initWithRoomId:roomId callSignalingRoomId:conferenceUserRoom.roomId andCallManager:self];
                    if (call)
                    {
                        [self->calls addObject:call];

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
        MXLogDebug(@"[MXCallManager] placeCallInRoom: ERROR: Cannot place call in %@. Members count: %tu", roomId, room.summary.membersCount.joined);

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
        case MXEventTypeCallAssertedIdentity:
        case MXEventTypeCallAssertedIdentityUnstable:
            [self handleCallAssertedIdentity:event];
            break;
        case MXEventTypeRoomMember:
            [self handleRoomMember:event];
            break;
        default:
            break;
    }
}

#pragma mark - Private methods
- (void)refreshTURNServer
{
    MXWeakify(self);
    [_mxSession.matrixRestClient turnServer:^(MXTurnServerResponse *turnServerResponse) {
        MXStrongifyAndReturnIfNil(self);

        MXLogDebug(@"[MXCallManager] refreshTURNServer: TTL:%tu URIs: %@", turnServerResponse.ttl, turnServerResponse.uris);

        if (turnServerResponse.uris)
        {
            self.turnServers = turnServerResponse;

            // Re-new when we're about to reach the TTL
            self->refreshTURNServerTimer = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:turnServerResponse.ttl * 0.9]
                                                                    interval:0
                                                                      target:self
                                                                    selector:@selector(refreshTURNServer)
                                                                    userInfo:nil
                                                                     repeats:NO];
            [[NSRunLoop mainRunLoop] addTimer:self->refreshTURNServerTimer forMode:NSDefaultRunLoopMode];
        }
        else
        {
            MXLogDebug(@"No TURN server: using fallback STUN server: %@", self->_fallbackSTUNServer);
            self.turnServers = nil;
        }

    } failure:^(NSError *error) {
        MXStrongifyAndReturnIfNil(self);

        MXLogDebug(@"[MXCallManager] refreshTURNServer: Failed to get TURN URIs.\n");
        MXLogDebug(@"Retry in 60s");
        self->refreshTURNServerTimer = [NSTimer timerWithTimeInterval:60 target:self selector:@selector(refreshTURNServer) userInfo:nil repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:self->refreshTURNServerTimer forMode:NSDefaultRunLoopMode];
    }];
}

- (void)handleCallInvite:(MXEvent *)event
{
    MXCallInviteEventContent *content = [MXCallInviteEventContent modelFromJSON:event.content];
    
    if (content.invitee && ![_mxSession.myUserId isEqualToString:content.invitee])
    {
        //  this call invite has a specific target, and it's not me, ignore
        return;
    }

    // Check expiration (usefull filter when receiving load of events when resuming the event stream)
    if (event.age < content.lifetime)
    {
        if ([event.sender isEqualToString:_mxSession.myUserId])
        {
            //  this is my event, ignore
            return;
        }
        
        // If it is an invite from the peer, we need to create the MXCall
        
        MXCall *call = [self callWithCallId:content.callId];
        if (!call)
        {
            NSString *nativeRoomId = event.roomId;
            MXRoom *room = [_mxSession roomWithRoomId:event.roomId];
            if (room.accountData.virtualRoomInfo.isVirtual)
            {
                nativeRoomId = room.accountData.virtualRoomInfo.nativeRoomId;
            }
            MXLogDebug(@"[MXCallManager] handleCallInvite: Creating call in %@", event.roomId);
            call = [[MXCall alloc] initWithRoomId:nativeRoomId callSignalingRoomId:event.roomId andCallManager:self];
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

- (void)notifyCallInvite:(NSString *)callId
{
    MXCall *call = [self callWithCallId:callId];

    if (call)
    {
        // If the app is resuming, wait for the complete end of the session resume in order
        // to check if the invite is still valid
        if (_mxSession.state == MXSessionStateSyncInProgress || _mxSession.state == MXSessionStateBackgroundSyncInProgress)
        {
            // The dispatch  on the main thread should be enough.
            // It means that the sync response that contained the invite (and possibly its end
            // of validity) has been fully parsed.
            MXWeakify(self);
            dispatch_async(dispatch_get_main_queue(), ^{
                MXStrongifyAndReturnIfNil(self);
                [self notifyCallInvite:callId];
            });
        }
        else if (call.state < MXCallStateConnected)
        {
            // If the call is still in ringing state, notify the app
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXCallManagerNewCall object:call userInfo:nil];
        }
    }
}

- (void)handleCallAnswer:(MXEvent *)event
{
    MXCallAnswerEventContent *content = [MXCallAnswerEventContent modelFromJSON:event.content];

    MXCall *call = [self callWithCallId:content.callId];
    if (call)
    {
        [call handleCallEvent:event];
    }
}

- (void)handleCallSelectAnswer:(MXEvent *)event
{
    MXCallSelectAnswerEventContent *content = [MXCallSelectAnswerEventContent modelFromJSON:event.content];

    MXCall *call = [self callWithCallId:content.callId];
    if (call)
    {
        [call handleCallEvent:event];
    }
}

- (void)handleCallHangup:(MXEvent *)event
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

- (void)handleCallCandidates:(MXEvent *)event
{
    MXCallCandidatesEventContent *content = [MXCallCandidatesEventContent modelFromJSON:event.content];

    // Forward the event to the MXCall object
    MXCall *call = [self callWithCallId:content.callId];
    if (call)
    {
        [call handleCallEvent:event];
    }
}

- (void)handleCallReject:(MXEvent *)event
{
    MXCallRejectEventContent *content = [MXCallRejectEventContent modelFromJSON:event.content];

    // Forward the event to the MXCall object
    MXCall *call = [self callWithCallId:content.callId];
    if (call)
    {
        [call handleCallEvent:event];
    }
}

- (void)handleCallNegotiate:(MXEvent *)event
{
    MXCallNegotiateEventContent *content = [MXCallNegotiateEventContent modelFromJSON:event.content];

    // Check expiration if provided (useful filter when receiving load of events when resuming the event stream)
    if (content.lifetime == 0 || event.age < content.lifetime)
    {
        if ([event.sender isEqualToString:_mxSession.myUserId] &&
            [content.partyId isEqualToString:_mxSession.myDeviceId])
        {
            //  this is a remote echo, ignore
            return;
        }
        
        MXCall *call = [self callWithCallId:content.callId];
        if (call)
        {
            [call handleCallEvent:event];
        }
    }
}

- (void)handleCallReplaces:(MXEvent *)event
{
    MXCallReplacesEventContent *content = [MXCallReplacesEventContent modelFromJSON:event.content];
    
    // Check expiration (useful filter when receiving load of events when resuming the event stream)
    if (event.age < content.lifetime)
    {
        if ([event.sender isEqualToString:_mxSession.myUserId] &&
            [content.partyId isEqualToString:_mxSession.myDeviceId])
        {
            //  this is a remote echo, ignore
            return;
        }
        
        MXCall *call = [self callWithCallId:content.callId];
        if (call)
        {
            [call handleCallEvent:event];
        }
    }
}

- (void)handleCallRejectReplacement:(MXEvent *)event
{
    MXCallRejectReplacementEventContent *content = [MXCallRejectReplacementEventContent modelFromJSON:event.content];
    
    // Forward the event to the MXCall object
    MXCall *call = [self callWithCallId:content.callId];
    if (call)
    {
        [call handleCallEvent:event];
    }
}

- (void)handleCallAssertedIdentity:(MXEvent *)event
{
    //  check handling allowed
    if (![MXSDKOptions sharedInstance].handleCallAssertedIdentityEvents)
    {
        return;
    }
    
    MXCallAssertedIdentityEventContent *content = [MXCallAssertedIdentityEventContent modelFromJSON:event.content];
    
    // Forward the event to the MXCall object
    MXCall *call = [self callWithCallId:content.callId];
    if (call)
    {
        if (content.assertedIdentity.userId)
        {
            //  do a native lookup first
            
            MXWeakify(self);
            
            [self getNativeUserFrom:content.assertedIdentity.userId success:^(MXThirdPartyUserInstance * _Nonnull user) {
                MXStrongifyAndReturnIfNil(self);
                
                MXAssertedIdentityModel *assertedIdentity = content.assertedIdentity;
                
                //  fetch the native user
                MXUser *mxUser = [self.mxSession userWithUserId:user.userId];
                
                if (mxUser)
                {
                    assertedIdentity = [[MXAssertedIdentityModel alloc] initWithUser:mxUser];
                }
                else
                {
                    assertedIdentity.userId = user.userId;
                }
                
                //  use the updated asserted identity
                call.assertedIdentity = assertedIdentity;
            } failure:nil];
        }
        else
        {
            //  no need to a native lookup, directly pass the identity
            call.assertedIdentity = content.assertedIdentity;
        }
    }
}

- (void)handleRoomMember:(MXEvent *)event
{
    MXRoomMemberEventContent *content = [MXRoomMemberEventContent modelFromJSON:event.content];
    
    if ([MXTools membership:content.membership] == MXMembershipInvite)
    {
        //  a room invite
        MXRoom *room = [_mxSession roomWithRoomId:event.roomId];
        NSString *directUserId = room.directUserId;
        
        if (!directUserId && content.isDirect)
        {
            directUserId = event.sender;
        }
        
        if (directUserId)
        {
            [self getNativeUserFrom:directUserId success:^(MXThirdPartyUserInstance * _Nonnull user) {
                MXRoom *nativeRoom = [self.mxSession directJoinedRoomWithUserId:user.userId];
                if (nativeRoom)
                {
                    //  auto-accept this invite from the virtual room, if a direct room with the native user found
                    [room join:^{
                        MXLogDebug(@"[MXCallManager] handleRoomMember: auto-joined on virtual room successfully.");
                        
                        //  set account data on the room, if required
                        [self.mxSession.roomAccountDataUpdateDelegate updateAccountDataIfRequiredForRoom:room
                                                                                        withNativeRoomId:nativeRoom.roomId
                                                                                              completion:nil];
                    } failure:^(NSError *error) {
                        MXLogDebug(@"[MXCallManager] handleRoomMember: auto-join on virtual room failed with error: %@", error);
                        
                        if (error.code == kMXRoomAlreadyJoinedErrorCode)
                        {
                            //  set account data on the room, if required
                            [self.mxSession.roomAccountDataUpdateDelegate updateAccountDataIfRequiredForRoom:room
                                                                                            withNativeRoomId:nativeRoom.roomId
                                                                                                  completion:nil];
                        }
                    }];
                }
            } failure:nil];
        }
    }
}

- (void)handleCallStateDidChangeNotification:(NSNotification *)notification
{
#if TARGET_OS_IPHONE
    MXCall *call = notification.object;
    
    switch (call.state) {
        case MXCallStateCreateOffer:
            [self.callKitAdapter startCall:call];
            break;
        case MXCallStateRinging:
            [self.callKitAdapter reportIncomingCall:call];
            break;
        case MXCallStateConnecting:
            [self.callKitAdapter reportCall:call startedConnectingAtDate:nil];
            break;
        case MXCallStateConnected:
            [self.callKitAdapter reportCall:call connectedAtDate:nil];
            break;
        case MXCallStateOnHold:
            [self.callKitAdapter reportCall:call onHold:YES];
            break;
        case MXCallStateEnded:
            [self.callKitAdapter endCall:call];
            break;
        default:
            break;
    }
#endif
}

- (void)handleCallSupportHoldingStatusDidChange:(NSNotification *)notification
{
#if TARGET_OS_IPHONE
    MXCall *call = notification.object;
    
    [self.callKitAdapter updateSupportsHoldingForCall:call];
#endif
}

- (void)unregisterFromNotifications
{
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    
    // Do not handle any call state change notifications
    [notificationCenter removeObserver:self name:kMXCallStateDidChange object:nil];
    
    // Do not handle any call supports holding status change notifications
    [notificationCenter removeObserver:self name:kMXCallSupportsHoldingStatusDidChange object:nil];
    
    // Don't track MXSession's state
    if (sessionStateObserver)
    {
        [notificationCenter removeObserver:sessionStateObserver name:kMXSessionStateDidChangeNotification object:_mxSession];
        sessionStateObserver = nil;
    }
}

- (void)setTurnServers:(MXTurnServerResponse *)turnServers
{
    _turnServers = turnServers;
    
    self.turnServersReceived = YES;
}

- (void)setTurnServersReceived:(BOOL)turnServersReceived
{
    _turnServersReceived = turnServersReceived;
    
    if (_turnServersReceived)
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXCallManagerTurnServersReceived object:self];
    }
}

#pragma mark - Transfer

- (void)transferCall:(MXCall *)callWithTransferee
                  to:(MXUserModel *)target
      withTransferee:(MXUserModel *)transferee
        consultFirst:(BOOL)consultFirst
             success:(void (^)(NSString * _Nullable newCallId))success
             failure:(void (^)(NSError * _Nullable error))failure
{
    if (callWithTransferee.isConferenceCall)
    {
        //  it's not intended to transfer conference calls
        if (failure)
        {
            failure(nil);
        }
        return;
    }
    
    dispatch_group_t virtualUserCheckGroup = dispatch_group_create();
    
    __block NSString *targetUserId = target.userId;
    
    if (self.virtualRoomsSupported)
    {
        dispatch_group_enter(virtualUserCheckGroup);
        [self getVirtualUserFrom:targetUserId success:^(MXThirdPartyUserInstance * _Nonnull user) {
            targetUserId = user.userId;
            dispatch_group_leave(virtualUserCheckGroup);
        } failure:^(NSError * _Nullable error) {
            dispatch_group_leave(virtualUserCheckGroup);
        }];
    }
    
    dispatch_group_notify(virtualUserCheckGroup, dispatch_get_main_queue(), ^{
        target.userId = targetUserId;
        
        MXWeakify(self);
        
        //  find the active call with target
        
        [self activeCallWithUser:targetUserId completion:^(MXCall * _Nullable call) {
            
            MXStrongifyAndReturnIfNil(self);
            
            //  define continue block
            void(^continueBlock)(MXCall *) = ^(MXCall *callWithTarget) {
                
                //  find a suitable room (which only consists three users: self, the transferee and the target)
                
                MXStrongifyAndReturnIfNil(self);
                
                if (MXSDKOptions.sharedInstance.callTransferType == MXCallTransferTypeBridged)
                {
                    if (consultFirst)
                    {
                        //  consult with the target
                        if (callWithTarget.isOnHold)
                        {
                            [callWithTarget hold:NO];
                        }
                        
                        if (success)
                        {
                            success(nil);
                        }
                    }
                    else
                    {
                        //  generate a new call id
                        NSString *newCallId = [[NSUUID UUID] UUIDString];
                        
                        dispatch_group_t dispatchGroup = dispatch_group_create();
                        dispatch_group_enter(dispatchGroup);
                        
                        if (callWithTarget)
                        {
                            //  send replaces event to target
                            [callWithTarget transferToRoom:nil
                                                      user:transferee
                                                createCall:nil
                                                 awaitCall:newCallId
                                                   success:^(NSString * _Nonnull eventId) {
                                dispatch_group_leave(dispatchGroup);
                            } failure:failure];
                        }
                        else
                        {
                            dispatch_group_leave(dispatchGroup);
                        }
                        
                        dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
                            //  send replaces event to transferee
                            [callWithTransferee transferToRoom:nil
                                                          user:target
                                                    createCall:newCallId
                                                     awaitCall:nil
                                                       success:^(NSString * _Nonnull eventId) {
                                if (success)
                                {
                                    success(newCallId);
                                }
                            } failure:failure];
                        });
                    }
                }
                else if (MXSDKOptions.sharedInstance.callTransferType == MXCallTransferTypeLocal)
                {
                    [self callTransferRoomWithUsers:@[targetUserId, transferee.userId] completion:^(MXRoom * _Nullable transferRoom, BOOL isNewRoom) {
                        
                        if (!transferRoom)
                        {
                            //  A room cannot be found/created
                            if (failure)
                            {
                                failure(nil);
                            }
                            return;
                        }
                        
                        if (consultFirst)
                        {
                            //  consult with the target
                            if (callWithTarget.isOnHold)
                            {
                                [callWithTarget hold:NO];
                            }
                            
                            if (success)
                            {
                                success(nil);
                            }
                        }
                        else
                        {
                            //  generate a new call id
                            NSString *newCallId = [[NSUUID UUID] UUIDString];
                            
                            dispatch_group_t dispatchGroup = dispatch_group_create();
                            dispatch_group_enter(dispatchGroup);

                            if (callWithTarget)
                            {
                                [callWithTarget hangup];
                                
                                //  send replaces event to target
                                [callWithTarget transferToRoom:transferRoom.roomId
                                                          user:transferee
                                                    createCall:nil
                                                     awaitCall:newCallId
                                                       success:^(NSString * _Nonnull eventId) {
                                    dispatch_group_leave(dispatchGroup);
                                } failure:failure];
                            }
                            else
                            {
                                dispatch_group_leave(dispatchGroup);
                            }
                            
                            dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
                                if (callWithTransferee.isOnHold)
                                {
                                    [callWithTransferee hold:NO];
                                }
                                //  send replaces event to transferee
                                [callWithTransferee transferToRoom:transferRoom.roomId
                                                              user:target
                                                        createCall:newCallId
                                                         awaitCall:nil
                                                           success:^(NSString * _Nonnull eventId) {
                                    if (isNewRoom)
                                    {
                                        //  if was a newly created room, send invites after replaces events
                                        [transferRoom inviteUser:target.userId success:nil failure:failure];
                                        [transferRoom inviteUser:transferee.userId success:nil failure:failure];
                                    }
                                    
                                    if (success)
                                    {
                                        success(newCallId);
                                    }
                                } failure:failure];
                            });
                        }
                        
                    }];
                }
            };
            
            if (call)
            {
                if (consultFirst)
                {
                    call.callWithTransferee = callWithTransferee;
                    call.transferee = transferee;
                    call.transferTarget = target;
                    call.consulting = YES;
                }
                continueBlock(call);
            }
            else
            {
                //  we're not in a call with target
                
                if (consultFirst)
                {
                    MXWeakify(self);
                    
                    [self directCallableRoomWithUser:target.userId timeout:kMXCallDirectRoomJoinTimeout completion:^(MXRoom * _Nullable room, NSError * _Nullable error) {
                        
                        MXStrongifyAndReturnIfNil(self);
                        
                        if (room == nil)
                        {
                            //  could not find/create a direct room with target
                            if (failure)
                            {
                                failure(nil);
                            }
                            return;
                        }
                        
                        //  place a new audio call to the target to consult the transfer
                        [self placeCallInRoom:room.roomId withVideo:NO success:^(MXCall * _Nonnull call) {
                            
                            //  mark the call with target & transferee as consulting
                            call.callWithTransferee = callWithTransferee;
                            call.transferee = transferee;
                            call.transferTarget = target;
                            call.consulting = YES;
                            
                            continueBlock(call);
                        } failure:^(NSError * _Nullable error) {
                            MXLogDebug(@"[MXCallManager] transferCall: couldn't call the target: %@", error);
                            if (failure)
                            {
                                failure(error);
                            }
                        }];
                        
                    }];
                }
                else
                {
                    //  we don't need to consult, so we can continue without an active call with the target
                    continueBlock(nil);
                }
            }
        }];
    });
}

/// Attempts to find a room with the given users only. If not found, tries to create. If fails, completion will be called with a nil room.
/// @param userIds User IDs array to look for
/// @param completion Completion block
- (void)callTransferRoomWithUsers:(NSArray<NSString *> *)userIds
                       completion:(void (^ _Nonnull)(MXRoom * _Nullable room, BOOL isNewRoom))completion
{
    __block MXRoom *resultRoom = nil;
    
    dispatch_group_t roomGroup = dispatch_group_create();
    
    for (MXRoom *room in self.mxSession.rooms)
    {
        dispatch_group_enter(roomGroup);
        
        [room state:^(MXRoomState *roomState) {
            
            NSArray<NSString *> *roomUserIds = [roomState.members.joinedMembers valueForKey:@"userId"];
            if (roomState.membersCount.joined == 3) //  ignore other rooms (which might have these users but some extra ones too)
            {
                NSSet *roomUserIdSet = [NSSet setWithArray:roomUserIds];
                NSSet *desiredUserIdSet = [NSSet setWithArray:userIds];
                if ([desiredUserIdSet isSubsetOfSet:roomUserIdSet])    //  if all userIds exist in roomUserIds
                {
                    resultRoom = room;
                }
            }
            
            dispatch_group_leave(roomGroup);
        }];
    }
    
    dispatch_group_notify(roomGroup, dispatch_get_main_queue(), ^{
        if (resultRoom)
        {
            completion(resultRoom, NO);
        }
        else
        {
            //  no room found, create a new one
            
            [self.mxSession canEnableE2EByDefaultInNewRoomWithUsers:userIds success:^(BOOL canEnableE2E) {
                
                MXRoomCreationParameters *roomCreationParameters = [MXRoomCreationParameters new];
                roomCreationParameters.visibility = kMXRoomDirectoryVisibilityPrivate;
                roomCreationParameters.preset = kMXRoomPresetTrustedPrivateChat;
                roomCreationParameters.inviteArray = nil;   //  intentionally do not invite yet users

                if (canEnableE2E)
                {
                    roomCreationParameters.initialStateEvents = @[
                                                                  [MXRoomCreationParameters initialStateEventForEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm
                                                                  ]];
                }

                [self.mxSession createRoomWithParameters:roomCreationParameters success:^(MXRoom *room) {
                    completion(room, YES);
                } failure:^(NSError *error) {
                    completion(nil, NO);
                }];

            } failure:^(NSError *error) {
                completion(nil, NO);
            }];
        }
    });
}

/// Tries to find a direct & callable room with the given user. If not such a room found, tries to create it and then waits for the other party to join.
/// @param userId The user id to check.
/// @param timeout The timeout for the invited user to join the room, in case of the room is newly created (in seconds).
/// @param completion Completion block.
- (void)directCallableRoomWithUser:(NSString * _Nonnull)userId
                           timeout:(NSTimeInterval)timeout
                        completion:(void (^_Nonnull)(MXRoom* _Nullable room, NSError * _Nullable error))completion
{
    MXRoom *room = [self.mxSession directJoinedRoomWithUserId:userId];
    if (room)
    {
        [room state:^(MXRoomState *roomState) {
            MXMembership membership = [roomState.members memberWithUserId:userId].membership;
            
            if (membership == MXMembershipJoin)
            {
                //  other party already joined, return the room
                completion(room, nil);
            }
            else if (membership == MXMembershipInvite)
            {
                //  Wait for other party to join before returning the room
                __block BOOL joined = NO;
                
                __block id listener = [room listenToEventsOfTypes:@[kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                    if ([event.sender isEqualToString:userId])
                    {
                        MXRoomMemberEventContent *content = [MXRoomMemberEventContent modelFromJSON:event.content];
                        if ([MXTools membership:content.membership] == MXMembershipJoin)
                        {
                            joined = YES;
                            [room removeListener:listener];
                            dispatch_async(dispatch_get_main_queue(), ^{
                                completion(room, nil);
                            });
                        }
                    }
                }];
                
                //  implement the timeout
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, timeout * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    if (!joined)
                    {
                        //  user failed to join within the given time
                        completion(nil, nil);
                    }
                });
            }
            else
            {
                completion(nil, nil);
            }
        }];
    }
    else
    {
        //  we're not in a direct room with target, create it
        [self.mxSession canEnableE2EByDefaultInNewRoomWithUsers:@[userId] success:^(BOOL canEnableE2E) {
            
            MXRoomCreationParameters *roomCreationParameters = [MXRoomCreationParameters parametersForDirectRoomWithUser:userId];
            roomCreationParameters.visibility = kMXRoomDirectoryVisibilityPrivate;

            if (canEnableE2E)
            {
                roomCreationParameters.initialStateEvents = @[
                                                              [MXRoomCreationParameters initialStateEventForEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm
                                                              ]];
            }

            [self.mxSession createRoomWithParameters:roomCreationParameters success:^(MXRoom *room) {
                //  wait for other party to join
                return [self directCallableRoomWithUser:userId timeout:timeout completion:completion];
            } failure:^(NSError *error) {
                completion(nil, error);
            }];

        } failure:^(NSError *error) {
            completion(nil, error);
        }];
    }
}

/// Tries to find an active call to a given user. If fails, completion will be called with a nil call.
/// @param userId The user id to check.
/// @param completion Completion block.
- (void)activeCallWithUser:(NSString * _Nonnull)userId
                completion:(void (^_Nonnull)(MXCall* _Nullable call))completion
{
    __block MXCall *resultCall = nil;
    
    dispatch_group_t callGroup = dispatch_group_create();
    
    for (MXCall *call in calls)
    {
        if (call.isConferenceCall)
        {
            continue;
        }
        if (call.state == MXCallStateEnded)
        {
            continue;
        }
        if ([call.callerId isEqualToString:userId])
        {
            resultCall = call;
            break;
        }
        
        dispatch_group_enter(callGroup);
        
        [call calleeId:^(NSString * _Nonnull calleeId) {
            if ([calleeId isEqualToString:userId])
            {
                resultCall = call;
            }
            dispatch_group_leave(callGroup);
        }];
    }
    
    dispatch_group_notify(callGroup, dispatch_get_main_queue(), ^{
        completion(resultCall);
    });
}

#pragma mark - Conference call

// Copied from vector-web:
// FIXME: This currently forces Vector to try to hit the matrix.org AS for conferencing.
// This is bad because it prevents people running their own ASes from being used.
// This isn't permanent and will be customisable in the future: see the proposal
// at docs/conferencing.md for more info.
NSString *const kMXCallManagerConferenceUserPrefix  = @"@fs_";
NSString *const kMXCallManagerConferenceUserDomain  = @"matrix.org";

- (void)handleConferenceUserUpdate:(MXRoomMember *)conferenceUserMember inRoom:(NSString *)roomId
{
    if (_mxSession.state == MXSessionStateRunning)
    {
        if (conferenceUserMember.membership == MXMembershipJoin)
        {
            // Broadcast the ongoing conference call
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXCallManagerConferenceStarted object:roomId userInfo:nil];
        }
        else if (conferenceUserMember.membership == MXMembershipLeave)
        {
            // Broadcast the end of the ongoing conference call
            [[NSNotificationCenter defaultCenter] postNotificationName:kMXCallManagerConferenceFinished object:roomId userInfo:nil];
        }
    }
}

+ (NSString *)conferenceUserIdForRoom:(NSString *)roomId
{
    // Apply the same algo as other matrix clients
    NSString *base64RoomId = [[roomId dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    base64RoomId = [base64RoomId stringByReplacingOccurrencesOfString:@"=" withString:@""];

    return [NSString stringWithFormat:@"%@%@:%@", kMXCallManagerConferenceUserPrefix, base64RoomId, kMXCallManagerConferenceUserDomain];
}

+ (BOOL)isConferenceUser:(NSString *)userId
{
    BOOL isConferenceUser = NO;

    if ([userId hasPrefix:kMXCallManagerConferenceUserPrefix])
    {
        NSString *base64part = [userId substringWithRange:NSMakeRange(4, [userId rangeOfString:@":"].location - 4)];
        if (base64part)
        {
            NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:base64part options:0];
            if (decodedData)
            {
                NSString *decoded = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
                if (decoded)
                {
                    isConferenceUser = [MXTools isMatrixRoomIdentifier:decoded];
                }
            }
        }
    }

    return isConferenceUser;
}

+ (BOOL)canPlaceConferenceCallInRoom:(MXRoom *)room roomState:(MXRoomState *)roomState
{
    BOOL canPlaceConferenceCallInRoom = NO;

    if (roomState.isOngoingConferenceCall)
    {
        // All room members can join an existing conference call
        canPlaceConferenceCallInRoom = YES;
    }
    else
    {
        MXRoomPowerLevels *powerLevels = roomState.powerLevels;
        NSInteger oneSelfPowerLevel = [powerLevels powerLevelOfUserWithUserID:room.mxSession.myUserId];

        // Only member with invite power level can create a conference call
        if (oneSelfPowerLevel >= powerLevels.invite)
        {
            canPlaceConferenceCallInRoom = YES;
        }
    }

    return canPlaceConferenceCallInRoom;
}

/**
 Make sure the conference user is in the passed room.

 It is mandatory before starting the conference call.

 @param room the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)inviteConferenceUserToRoom:(MXRoom *)room
                           success:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure
{
    NSString *conferenceUserId = [MXCallManager conferenceUserIdForRoom:room.roomId];

    [room members:^(MXRoomMembers *roomMembers) {
        MXRoomMember *conferenceUserMember = [roomMembers memberWithUserId:conferenceUserId];
        if (conferenceUserMember && conferenceUserMember.membership == MXMembershipJoin)
        {
            success();
        }
        else
        {
            [room inviteUser:conferenceUserId success:success failure:failure];
        }
    } failure:failure];
}

/**
 Get the room with the conference user dedicated for the passed room.

 @param roomId the room id.
 @param success A block object called when the operation succeeds. 
                It returns the private room with conference user.
 @param failure A block object called when the operation fails.
 */
- (void)conferenceUserRoomForRoom:(NSString*)roomId
                          success:(void (^)(MXRoom *conferenceUserRoom))success
                          failure:(void (^)(NSError *error))failure
{
    NSString *conferenceUserId = [MXCallManager conferenceUserIdForRoom:roomId];

    // Use an existing 1:1 with the conference user; else make one
    __block MXRoom *conferenceUserRoom;

    dispatch_group_t group = dispatch_group_create();
    for (MXRoom *room in _mxSession.rooms)
    {
        if (room.summary.isConferenceUserRoom)
        {
            dispatch_group_enter(group);

            [room state:^(MXRoomState *roomState) {
                if ([roomState.members memberWithUserId:conferenceUserId])
                {
                    conferenceUserRoom = room;
                }

                dispatch_group_leave(group);
            }];
        }
    }

    MXWeakify(self);
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        MXStrongifyAndReturnIfNil(self);

        if (conferenceUserRoom)
        {
            success(conferenceUserRoom);
        }
        else
        {
            [self.mxSession createRoom:@{
                                         @"preset": @"private_chat",
                                         @"invite": @[conferenceUserId]
                                         } success:^(MXRoom *room) {

                                             success(room);

                                         } failure:failure];
        }
    });
}

#pragma mark - PSTN

- (void)setPstnProtocol:(MXThirdPartyProtocol *)pstnProtocol
{
    _pstnProtocol = pstnProtocol;
    
    self.supportsPSTN = _pstnProtocol != nil;
}

- (void)setSupportsPSTN:(BOOL)supportsPSTN
{
    _supportsPSTN = supportsPSTN;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kMXCallManagerPSTNSupportUpdated object:self];
}

- (void)checkThirdPartyProtocols
{
    MXWeakify(self);
    [_mxSession.matrixRestClient thirdpartyProtocols:^(MXThirdpartyProtocolsResponse *response) {
        MXStrongifyAndReturnIfNil(self);
        
        MXThirdPartyProtocol *protocol = response.protocols[kMXProtocolVectorPSTN];
        
        if (!protocol)
        {
            protocol = response.protocols[kMXProtocolPSTN];
        }
        
        self.pstnProtocol = protocol;
        
        MXThirdPartyProtocol *sipNativeProtocol = response.protocols[kMXProtocolVectorSipNative];
        MXThirdPartyProtocol *sipVirtualProtocol = response.protocols[kMXProtocolVectorSipVirtual];
        
        self.virtualRoomsSupported = (sipNativeProtocol && sipVirtualProtocol);
        
    } failure:^(NSError *error) {
        MXLogDebug(@"Failed to check for third party protocols with error: %@", error);
        self.pstnProtocol = nil;
    }];
}

- (void)getThirdPartyUserFrom:(NSString *)phoneNumber
                      success:(void (^)(MXThirdPartyUserInstance * _Nonnull))success
                      failure:(void (^)(NSError * _Nullable))failure
{
    [_mxSession.matrixRestClient thirdpartyUsers:kMXProtocolVectorPSTN
                                          fields:@{
                                              kMXLoginIdentifierTypePhone: phoneNumber
                                          }
                                         success:^(MXThirdPartyUsersResponse *thirdpartyUsersResponse) {
        
        MXThirdPartyUserInstance * user = [thirdpartyUsersResponse.users firstObject];
        
        MXLogDebug(@"Succeeded to look up the phone number: %@", user.userId);
        
        if (user)
        {
            if (success)
            {
                success(user);
            }
        }
        else
        {
            if (failure)
            {
                failure(nil);
            }
        }
    } failure:^(NSError *error) {
        MXLogDebug(@"Failed to look up the phone number with error: %@", error);
        if (failure)
        {
            failure(error);
        }
    }];
}

- (void)placeCallAgainst:(NSString *)phoneNumber
               withVideo:(BOOL)video
                 success:(void (^)(MXCall * _Nonnull))success
                 failure:(void (^)(NSError * _Nullable))failure
{
    MXWeakify(self);
    [self getThirdPartyUserFrom:phoneNumber success:^(MXThirdPartyUserInstance *_Nonnull user) {
        MXStrongifyAndReturnIfNil(self);
        
        //  try to find a direct room with this user
        [self directCallableRoomWithUser:user.userId timeout:kMXCallDirectRoomJoinTimeout completion:^(MXRoom * _Nullable room, NSError * _Nullable error) {
            if (room)
            {
                //  room found, place the call in this room
                [self placeCallInRoom:room.roomId
                            withVideo:video
                              success:success
                              failure:failure];
            }
            else
            {
                //  no room found
                MXLogDebug(@"Failed to find a room for call with error: %@", error);
                if (failure)
                {
                    failure(error);
                }
            }
        }];
        
    } failure:failure];
}

#pragma mark - Virtual Rooms

- (void)setVirtualRoomsSupported:(BOOL)virtualRoomsSupported
{
    if (_virtualRoomsSupported != virtualRoomsSupported)
    {
        _virtualRoomsSupported = virtualRoomsSupported;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXCallManagerVirtualRoomsSupportUpdated
                                                            object:self];
    }
}

- (void)getVirtualUserFrom:(NSString *)userId
                   success:(void (^)(MXThirdPartyUserInstance * _Nonnull))success
                   failure:(void (^)(NSError * _Nullable))failure
{
    [_mxSession.matrixRestClient thirdpartyUsers:kMXProtocolVectorSipVirtual
                                          fields:@{
                                              @"native_mxid": userId
                                          }
                                         success:^(MXThirdPartyUsersResponse *thirdpartyUsersResponse) {
        
        MXThirdPartyUserInstance * user = [thirdpartyUsersResponse.users firstObject];
        
        MXLogDebug(@"[MXCallManager] getVirtualUserFrom: Succeeded to look up the virtual user: %@", user.userId);
        
        if (user && user.userId.length > 0)
        {
            if (success)
            {
                success(user);
            }
        }
        else
        {
            if (failure)
            {
                failure(nil);
            }
        }
    } failure:^(NSError *error) {
        MXLogDebug(@"[MXCallManager] getVirtualUserFrom: Failed to look up the virtual user with error: %@", error);
        if (failure)
        {
            failure(error);
        }
    }];
}

- (void)getNativeUserFrom:(NSString *)userId
                  success:(void (^)(MXThirdPartyUserInstance * _Nonnull))success
                  failure:(void (^)(NSError * _Nullable))failure
{
    [_mxSession.matrixRestClient thirdpartyUsers:kMXProtocolVectorSipNative
                                          fields:@{
                                              @"virtual_mxid": userId
                                          }
                                         success:^(MXThirdPartyUsersResponse *thirdpartyUsersResponse) {
        
        MXThirdPartyUserInstance * user = [thirdpartyUsersResponse.users firstObject];
        
        MXLogDebug(@"[MXCallManager] getNativeUserFrom: Succeeded to look up the native user: %@", user.userId);
        
        if (user && user.userId.length > 0)
        {
            if (success)
            {
                success(user);
            }
        }
        else
        {
            if (failure)
            {
                failure(nil);
            }
        }
    } failure:^(NSError *error) {
        MXLogDebug(@"[MXCallManager] getNativeUserFrom: Failed to look up the native user with error: %@", error);
        if (failure)
        {
            failure(error);
        }
    }];
}

/// Tries to find a direct & callable room with the given virtual user. If not such a room found, tries to create it as a virtual room and then waits for the other party to join.
/// @param userId The virtual user id to check.
/// @param timeout The timeout for the invited user to join the room, in case of the room is newly created (in seconds).
/// @param completion Completion block.
- (void)directCallableRoomWithVirtualUser:(NSString * _Nonnull)userId
                             nativeRoomId:(NSString * _Nonnull)nativeRoomId
                                  timeout:(NSTimeInterval)timeout
                               completion:(void (^_Nonnull)(MXRoom* _Nullable room, NSError * _Nullable error))completion
{
    MXRoom *room = [self.mxSession directJoinedRoomWithUserId:userId];
    if (room)
    {
        [room state:^(MXRoomState *roomState) {
            MXMembership membership = [roomState.members memberWithUserId:userId].membership;
            
            if (membership == MXMembershipJoin)
            {
                //  other party already joined
                
                //  set account data on the room, if required
                [self.mxSession.roomAccountDataUpdateDelegate updateAccountDataIfRequiredForRoom:room
                                                                                withNativeRoomId:nativeRoomId
                                                                                      completion:^(BOOL updated, NSError *error) {
                    if (updated)
                    {
                        completion(room, nil);
                    }
                    else
                    {
                        completion(nil, error);
                    }
                }];
            }
            else if (membership == MXMembershipInvite)
            {
                //  Wait for other party to join before returning the room
                __block BOOL joined = NO;
                
                __block id listener = [room listenToEventsOfTypes:@[kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                    if ([event.sender isEqualToString:userId])
                    {
                        MXRoomMemberEventContent *content = [MXRoomMemberEventContent modelFromJSON:event.content];
                        if ([MXTools membership:content.membership] == MXMembershipJoin)
                        {
                            joined = YES;
                            [room removeListener:listener];
                            dispatch_async(dispatch_get_main_queue(), ^{
                                completion(room, nil);
                            });
                        }
                    }
                }];
                
                //  implement the timeout
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, timeout * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    if (!joined)
                    {
                        //  user failed to join within the given time
                        completion(nil, nil);
                    }
                });
            }
            else
            {
                completion(nil, nil);
            }
        }];
    }
    else
    {
        //  we're not in a direct room with target, create it
        [self.mxSession canEnableE2EByDefaultInNewRoomWithUsers:@[userId] success:^(BOOL canEnableE2E) {
            
            MXRoomCreationParameters *roomCreationParameters = [MXRoomCreationParameters parametersForDirectRoomWithUser:userId];
            roomCreationParameters.visibility = kMXRoomDirectoryVisibilityPrivate;
            roomCreationParameters.creationContent = [MXRoomCreationParameters creationContentForVirtualRoomWithNativeRoomId:nativeRoomId];
            
            if (canEnableE2E)
            {
                roomCreationParameters.initialStateEvents = @[
                    [MXRoomCreationParameters initialStateEventForEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm]
                ];
            }

            [self.mxSession createRoomWithParameters:roomCreationParameters success:^(MXRoom *room) {
                //  set account data on the room, if required
                MXWeakify(self);
                [self.mxSession.roomAccountDataUpdateDelegate updateAccountDataIfRequiredForRoom:room
                                                                                withNativeRoomId:nativeRoomId
                                                                                      completion:^(BOOL updated, NSError *error) {
                    MXStrongifyAndReturnIfNil(self);
                    if (updated)
                    {
                        [self directCallableRoomWithUser:userId timeout:timeout completion:completion];
                    }
                    else
                    {
                        completion(nil, error);
                    }
                }];
            } failure:^(NSError *error) {
                completion(nil, error);
            }];

        } failure:^(NSError *error) {
            completion(nil, error);
        }];
    }
}

#pragma mark - Recent

- (NSArray<MXUser *> * _Nonnull)getRecentCalledUsers:(NSUInteger)maxNumberOfUsers
                                      ignoredUserIds:(NSArray<NSString*> * _Nullable)ignoredUserIds
{
    if (maxNumberOfUsers == 0)
    {
        return NSArray.array;
    }
    
    NSArray<MXRoom *> *rooms = _mxSession.rooms;
    
    if (rooms.count == 0)
    {
        return NSArray.array;
    }
    
    NSMutableArray *callEvents = [NSMutableArray arrayWithCapacity:rooms.count];
    
    for (MXRoom *room in rooms) {
        id<MXEventsEnumerator> enumerator = [room enumeratorForStoredMessagesWithTypeIn:@[kMXEventTypeStringCallInvite]];
        MXEvent *callEvent = enumerator.nextEvent;
        if (callEvent)
        {
            [callEvents addObject:callEvent];
        }
    }
    
    [callEvents sortUsingComparator:^NSComparisonResult(MXEvent * _Nonnull event1, MXEvent * _Nonnull event2) {
        return [@(event1.age) compare:@(event2.age)];
    }];
    
    NSMutableArray *users = [NSMutableArray arrayWithCapacity:callEvents.count];
    
    for (MXEvent *event in callEvents) {
        NSString *userId = nil;
        if ([event.sender isEqualToString:_mxSession.myUserId])
        {
            userId = [_mxSession directUserIdInRoom:event.roomId];
        }
        else
        {
            userId = event.sender;
        }
        
        if (userId && ![ignoredUserIds containsObject:userId])
        {
            MXUser *user = [_mxSession userWithUserId:userId];
            if (user)
            {
                [users addObject:user];
                if (users.count == maxNumberOfUsers)
                {
                    //  no need to go further
                    break;
                }
            }
        }
    }
    
    return users;
}

@end

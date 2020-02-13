/*
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

#import "MXKeyVerificationStatusResolver.h"

#import "MXSession.h"
#import "MXKeyVerificationByDMRequest.h"
#import "MXKeyVerificationRequest_Private.h"
#import "MXKeyVerification.h"
#import "MXKeyVerificationManager_Private.h"

#import "MXKeyVerificationCancel.h"


@interface MXKeyVerificationStatusResolver ()
@property (nonatomic, weak) MXKeyVerificationManager *manager;
@property (nonatomic) MXSession *mxSession;
@end


@implementation MXKeyVerificationStatusResolver

- (instancetype)initWithManager:(MXKeyVerificationManager*)manager matrixSession:(MXSession*)matrixSession;

{
    self = [super init];
    if (self)
    {
        self.manager = manager;
        self.mxSession = matrixSession;
    }
    return self;
}


- (nullable MXHTTPOperation *)keyVerificationWithKeyVerificationId:(NSString*)keyVerificationId
                                                             event:(MXEvent*)event
                                                         transport:(MKeyVerificationTransport)transport
                                                           success:(void(^)(MXKeyVerification *keyVerification))success
                                                           failure:(void(^)(NSError *error))failure
{
    MXHTTPOperation *operation;
    switch (transport)
    {
        case MKeyVerificationTransportDirectMessage:
        {
            operation = [self eventsInVerificationByDMThreadFromOriginalEventId:keyVerificationId inRoom:event.roomId success:^(MXEvent *originalEvent, NSArray<MXEvent*> *events) {

                if (!originalEvent)
                {
                    originalEvent = event;
                }

                MXKeyVerification *keyVerification = [self makeKeyVerificationFromOriginalDMEvent:originalEvent events:events];
                if (keyVerification)
                {
                    success(keyVerification);
                }
                else
                {
                    NSError *error = [NSError errorWithDomain:MXKeyVerificationErrorDomain
                                                         code:MXKeyVerificationUnknownIdentifier
                                                     userInfo:@{
                                                                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown id"]
                                                                }];
                    failure(error);
                }

            } failure:failure];
            break;
        }

        default:
            // Requests by to_device are not supported
            NSParameterAssert(NO);
            break;
    }

    return operation;
}

- (nullable MXHTTPOperation *)eventsInVerificationByDMThreadFromOriginalEventId:(NSString*)originalEventId
                                                                         inRoom:(NSString*)roomId
                                                                        success:(void(^)(MXEvent *originalEvent, NSArray<MXEvent*> *events))success
                                                                        failure:(void(^)(NSError *error))failure
{
    // Get all related events
    return [self.mxSession.aggregations referenceEventsForEvent:originalEventId inRoom:roomId from:nil limit:-1 success:^(MXAggregationPaginatedResponse * _Nonnull paginatedResponse) {
        success(paginatedResponse.originalEvent, paginatedResponse.chunk);
    } failure:failure];
}

- (nullable MXKeyVerification *)makeKeyVerificationFromOriginalDMEvent:(nullable MXEvent*)originalEvent events:(NSArray<MXEvent*> *)events
{
    MXKeyVerification *keyVerification;

    MXKeyVerificationRequest *request = [self verificationRequestInDMEvent:originalEvent events:events];

    if (request)
    {
        keyVerification = [MXKeyVerification new];
        keyVerification.request = request;

        keyVerification.state = [self stateFromRequestState:request.state andEvents:events];
    }

    return keyVerification;
}

- (nullable MXKeyVerificationByDMRequest*)verificationRequestInDMEvent:(MXEvent*)event events:(NSArray<MXEvent*> *)events
{
    MXKeyVerificationByDMRequest *request;
    if ([event.content[@"msgtype"] isEqualToString:kMXMessageTypeKeyVerificationRequest])
    {
        request = [[MXKeyVerificationByDMRequest alloc] initWithEvent:event andManager:self.manager];
        if (request)
        {
            NSString *myUserId = self.mxSession.myUser.userId;
            BOOL isFromMyUser = [event.sender isEqualToString:myUserId];
            request.isFromMyUser = isFromMyUser;

            MXEvent *firstEvent = events.firstObject;
            if (firstEvent.eventType == MXEventTypeKeyVerificationCancel)
            {
                // If the first event is a cancel, the request has been cancelled
                // by me or declined by the other
                if ([firstEvent.sender isEqualToString:myUserId])
                {
                    [request updateState:MXKeyVerificationRequestStateCancelledByMe notifiy:NO];
                }
                else
                {
                    [request updateState:MXKeyVerificationRequestStateCancelled notifiy:NO];
                }
            }
            else if (events.count)
            {
                // If there are events but no cancel event at first, the transaction
                // has started = the request has been accepted
                for (MXEvent *event in events)
                {
                    // In case the other sent a ready event, store its content
                    if (event.eventType == MXEventTypeKeyVerificationReady)
                    {
                        MXKeyVerificationReady *keyVerificationReady;
                        MXJSONModelSetMXJSONModel(keyVerificationReady, MXKeyVerificationReady, event.content);
                        request.acceptedData = keyVerificationReady;
                    }
                }
        
                [request updateState:MXKeyVerificationRequestStateAccepted notifiy:NO];
            }
            // There is only the request event. What is the status of it?
            else if (![self.manager isRequestStillPending:request])
            {
                [request updateState:MXKeyVerificationRequestStateExpired notifiy:NO];
            }
            else
            {
                [request updateState:MXKeyVerificationRequestStatePending notifiy:NO];
            }
        }
    }
    return request;
}


- (MXKeyVerificationState)stateFromRequestState:(MXKeyVerificationRequestState)requestState andEvents:(NSArray<MXEvent*> *)events
{
    MXKeyVerificationState state;
    switch (requestState)
    {
        case MXKeyVerificationRequestStatePending:
            state = MXKeyVerificationStateRequestPending;
            break;
        case MXKeyVerificationRequestStateExpired:
            state = MXKeyVerificationStateRequestExpired;
            break;
        case MXKeyVerificationRequestStateCancelled:
            state = MXKeyVerificationStateRequestCancelled;
            break;
        case MXKeyVerificationRequestStateCancelledByMe:
            state = MXKeyVerificationStateRequestCancelledByMe;
            break;
        case MXKeyVerificationRequestStateAccepted:
            state = [self computeTranscationStateWithEvents:events];
            break;
    }

    return state;
}

- (MXKeyVerificationState)computeTranscationStateWithEvents:(NSArray<MXEvent*> *)events
{
    for (MXEvent *event in events)
    {
        NSString *myUserId = self.mxSession.myUser.userId;

        switch (event.eventType)
        {
            case MXEventTypeKeyVerificationCancel:
            {
                MXKeyVerificationCancel *cancel;
                MXJSONModelSetMXJSONModel(cancel, MXKeyVerificationCancel.class, event.content);

                NSString *cancelCode = cancel.code;
                if ([cancelCode isEqualToString:MXTransactionCancelCode.user.value]
                    || [cancelCode isEqualToString:MXTransactionCancelCode.timeout.value])
                {
                    if ([event.sender isEqualToString:myUserId])
                    {
                        return MXKeyVerificationStateTransactionCancelledByMe;
                    }
                    else
                    {
                        return MXKeyVerificationStateTransactionCancelled;
                    }
                }
                else
                {
                    return MXKeyVerificationStateTransactionFailed;
                }
                break;
            }

            case MXEventTypeKeyVerificationDone:
                if ([event.sender isEqualToString:myUserId])
                {
                    return MXKeyVerificationStateVerified;
                }
                break;

            default:
                break;
        }
    }

    return MXKeyVerificationStateTransactionStarted;
}

@end

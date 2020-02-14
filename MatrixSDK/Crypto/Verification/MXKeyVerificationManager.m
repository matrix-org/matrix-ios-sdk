/*
 Copyright 2019 New Vector Ltd
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

#import "MXKeyVerificationManager.h"
#import "MXKeyVerificationManager_Private.h"

#import "MXSession.h"
#import "MXCrypto_Private.h"
#import "MXTools.h"

#import "MXTransactionCancelCode.h"

#import "MXKeyVerificationRequest_Private.h"
#import "MXKeyVerificationByDMRequest.h"
#import "MXKeyVerificationRequestJSONModel.h"

#import "MXKeyVerificationStatusResolver.h"


#pragma mark - Constants

NSString *const MXKeyVerificationErrorDomain = @"org.matrix.sdk.verification";
NSString *const MXKeyVerificationManagerNewRequestNotification       = @"MXKeyVerificationManagerNewRequestNotification";
NSString *const MXKeyVerificationManagerNotificationRequestKey       = @"MXKeyVerificationManagerNotificationRequestKey";
NSString *const MXKeyVerificationManagerNewTransactionNotification   = @"MXKeyVerificationManagerNewTransactionNotification";
NSString *const MXKeyVerificationManagerNotificationTransactionKey   = @"MXKeyVerificationManagerNotificationTransactionKey";

// Transaction timeout in seconds
NSTimeInterval const MXTransactionTimeout = 10 * 60.0;

// Request timeout in seconds
NSTimeInterval const MXRequestDefaultTimeout = 5 * 60.0;

static NSArray<MXEventTypeString> *kMXKeyVerificationManagerDMEventTypes;


@interface MXKeyVerificationManager ()
{
    // The queue to run background tasks
    dispatch_queue_t cryptoQueue;

    // All running transactions
    MXUsersDevicesMap<MXKeyVerificationTransaction*> *transactions;
    // Timer to cancel transactions
    NSTimer *transactionTimeoutTimer;

    // All pending requests
    // Request id -> request
    NSMutableDictionary<NSString*, MXKeyVerificationRequest*> *pendingRequestsMap;

    // Timer to cancel requests
    NSTimer *requestTimeoutTimer;

    MXKeyVerificationStatusResolver *statusResolver;
}
@end

@implementation MXKeyVerificationManager

#pragma mark - Public methods -

#pragma mark Requests

- (void)requestVerificationByDMWithUserId:(NSString*)userId
                                   roomId:(nullable NSString*)roomId
                             fallbackText:(NSString*)fallbackText
                                  methods:(NSArray<NSString*>*)methods
                                  success:(void(^)(MXKeyVerificationRequest *request))success
                                  failure:(void(^)(NSError *error))failure
{
    if (roomId)
    {
        [self requestVerificationByDMWithUserId2:userId roomId:roomId fallbackText:fallbackText methods:methods success:success failure:failure];
    }
    else
    {
        // Use an existing direct room if any
        MXRoom *room = [self.crypto.mxSession directJoinedRoomWithUserId:userId];
        if (room)
        {
            [self requestVerificationByDMWithUserId2:userId roomId:room.roomId fallbackText:fallbackText methods:methods success:success failure:failure];
        }
        else
        {
            // Create a new DM with E2E by default if possible
            [self.crypto.mxSession canEnableE2EByDefaultInNewRoomWithUsers:@[userId] success:^(BOOL canEnableE2E) {
                MXRoomCreationParameters *roomCreationParameters = [MXRoomCreationParameters parametersForDirectRoomWithUser:userId];
                
                if (canEnableE2E)
                {
                    roomCreationParameters.initialStateEvents = @[
                                                                  [MXRoomCreationParameters initialStateEventForEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm
                                                                   ]];
                }

                [self.crypto.mxSession createRoomWithParameters:roomCreationParameters success:^(MXRoom *room) {
                    [self requestVerificationByDMWithUserId2:userId roomId:room.roomId fallbackText:fallbackText methods:methods success:success failure:failure];
                } failure:failure];
            } failure:failure];
        }
    }
}

- (void)requestVerificationByDMWithUserId2:(NSString*)userId
                                    roomId:(NSString*)roomId
                              fallbackText:(NSString*)fallbackText
                                   methods:(NSArray<NSString*>*)methods
                                   success:(void(^)(MXKeyVerificationRequest *request))success
                                   failure:(void(^)(NSError *error))failure
{
    NSLog(@"[MXKeyVerification] requestVerificationByDMWithUserId: %@. RoomId: %@", userId, roomId);
    
    MXKeyVerificationRequestJSONModel *request = [MXKeyVerificationRequestJSONModel new];
    request.body = fallbackText;
    request.methods = methods;
    request.to = userId;
    request.fromDevice = _crypto.myDevice.deviceId;
    
    [self sendEventOfType:kMXEventTypeStringRoomMessage toRoom:roomId content:request.JSONDictionary success:^(NSString *eventId) {
        
        // Build the corresponding the event
        MXRoom *room = [self.crypto.mxSession roomWithRoomId:roomId];
        MXEvent *event = [room fakeRoomMessageEventWithEventId:eventId andContent:request.JSONDictionary];
        
        MXKeyVerificationRequest *request = [self verificationRequestInDMEvent:event];
        [request updateState:MXKeyVerificationRequestStatePending notifiy:YES];
        [self addPendingRequest:request notify:NO];
        
        success(request);
    } failure:failure];
}

#pragma mark Current requests

- (NSArray<MXKeyVerificationRequest*> *)pendingRequests
{
    return pendingRequestsMap.allValues;
}


#pragma mark Transactions

- (void)beginKeyVerificationWithUserId:(NSString*)userId
                           andDeviceId:(NSString*)deviceId
                                method:(NSString*)method
                               success:(void(^)(MXKeyVerificationTransaction *transaction))success
                               failure:(void(^)(NSError *error))failure
{
    [self beginKeyVerificationWithUserId:userId andDeviceId:deviceId dmRoomId:nil dmEventId:nil method:method success:success failure:failure];
}

- (void)beginKeyVerificationFromRequest:(MXKeyVerificationRequest*)request
                                 method:(NSString*)method
                                success:(void(^)(MXKeyVerificationTransaction *transaction))success
                                failure:(void(^)(NSError *error))failure
{
    NSLog(@"[MXKeyVerification] beginKeyVerificationFromRequest: event: %@", request.requestId);
    
    // Sanity checks
    if (!request.otherDevice)
    {
        NSError *error = [NSError errorWithDomain:MXKeyVerificationErrorDomain
                                             code:MXKeyVerificationUnknownDeviceCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"from_device not found"]
                                                    }];
        failure(error);
        return;
    }
    
    if (request.state != MXKeyVerificationRequestStateAccepted)
    {
        NSError *error = [NSError errorWithDomain:MXKeyVerificationErrorDomain
                                             code:MXKeyVerificationInvalidStateCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The verification request has not been accepted. Current state: %@", @(request.state)]
                                                    }];
        failure(error);
        return;
    }
    
    if ([request isKindOfClass:MXKeyVerificationByDMRequest.class])
    {
        MXKeyVerificationByDMRequest *requestByDM = (MXKeyVerificationByDMRequest*)request;
        [self beginKeyVerificationWithUserId:request.otherUser andDeviceId:request.otherDevice dmRoomId:requestByDM.roomId dmEventId:requestByDM.eventId method:method success:^(MXKeyVerificationTransaction *transaction) {
            [self removePendingRequestWithRequestId:request.requestId];
            success(transaction);
        } failure:failure];
    }
    else
    {
        // Requests by to_device are not supported
        NSParameterAssert(NO);
    }
}

- (void)beginKeyVerificationWithUserId:(NSString*)userId
                           andDeviceId:(NSString*)deviceId
                              dmRoomId:(nullable NSString*)dmRoomId
                             dmEventId:(nullable NSString*)dmEventId
                                method:(NSString*)method
                               success:(void(^)(MXKeyVerificationTransaction *transaction))success
                               failure:(void(^)(NSError *error))failure
{
    NSLog(@"[MXKeyVerification] beginKeyVerification: device: %@:%@ roomId: %@ method:%@", userId, deviceId, dmRoomId, method);

    // Make sure we have other device keys
    [self loadDeviceWithDeviceId:deviceId andUserId:userId success:^(MXDeviceInfo *otherDevice) {

        MXKeyVerificationTransaction *transaction;
        NSError *error;

        // We support only SAS at the moment
        if ([method isEqualToString:MXKeyVerificationMethodSAS])
        {
            MXOutgoingSASTransaction *sasTransaction = [[MXOutgoingSASTransaction alloc] initWithOtherDevice:otherDevice andManager:self];

            // Detect verification by DM
            if (dmRoomId)
            {
                [sasTransaction setDirectMessageTransportInRoom:dmRoomId originalEvent:dmEventId];
            }

            [sasTransaction start];

            transaction = sasTransaction;
            [self addTransaction:transaction];
        }
        else
        {
            error = [NSError errorWithDomain:MXKeyVerificationErrorDomain
                                        code:MXKeyVerificationUnsupportedMethodCode
                                    userInfo:@{
                                               NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsupported verification method: %@", method]
                                               }];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (transaction)
            {
                success(transaction);
            }
            else
            {
                failure(error);
            }
        });

    } failure:^(NSError *error) {
        NSLog(@"[MXKeyVerification] beginKeyVerification: Error: %@", error);
        failure(error);
    }];
}

- (void)transactions:(void(^)(NSArray<MXKeyVerificationTransaction*> *transactions))complete
{
    MXWeakify(self);
    dispatch_async(self->cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        NSArray<MXKeyVerificationTransaction*> *transactions = self->transactions.allObjects;
        dispatch_async(dispatch_get_main_queue(), ^{
            complete(transactions);
        });
    });
}


#pragma mark Verification status

- (nullable MXHTTPOperation *)keyVerificationFromKeyVerificationEvent:(MXEvent*)event
                                                              success:(void(^)(MXKeyVerification *keyVerification))success
                                                              failure:(void(^)(NSError *error))failure
{
    MKeyVerificationTransport transport = MKeyVerificationTransportToDevice;
    MXKeyVerification *keyVerification;

    // Check if it is a Verification by DM Event
    NSString *keyVerificationId = [self keyVerificationIdFromDMEvent:event];
    if (keyVerificationId)
    {
        transport = MKeyVerificationTransportDirectMessage;
    }
    else
    {
        NSError *error = [NSError errorWithDomain:MXKeyVerificationErrorDomain
                                             code:MXKeyVerificationUnknownIdentifier
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown id or not supported transport"]
                                                    }];
        failure(error);
        return nil;
    }

    keyVerification = [self pendingKeyVerificationWithKeyVerificationId:keyVerificationId];
    if (keyVerification)
    {
        success(keyVerification);
        return nil;
    }


    return [statusResolver keyVerificationWithKeyVerificationId:keyVerificationId event:event transport:transport success:success failure:failure];
}

- (nullable NSString *)keyVerificationIdFromDMEvent:(MXEvent*)event
{
    NSString *keyVerificationId;

    // Original event or one of the thread?
    if (event.eventType == MXEventTypeRoomMessage
        && [event.content[@"msgtype"] isEqualToString:kMXMessageTypeKeyVerificationRequest])
    {
        keyVerificationId = event.eventId;
    }
    else if ([self isVerificationByDMEventType:event.type])
    {
        MXKeyVerificationJSONModel *keyVerificationJSONModel;
        MXJSONModelSetMXJSONModel(keyVerificationJSONModel, MXKeyVerificationJSONModel, event.content);
        keyVerificationId = keyVerificationJSONModel.relatedEventId;
    }

    return keyVerificationId;
}

- (nullable MXKeyVerification *)pendingKeyVerificationWithKeyVerificationId:(NSString*)keyVerificationId
{
    MXKeyVerification *keyVerification;

    // First, check if this is a transaction in progress
    MXKeyVerificationTransaction *transaction = [self transactionWithTransactionId:keyVerificationId];
    if (transaction)
    {
        keyVerification = [MXKeyVerification new];
        keyVerification.transaction = transaction;
        keyVerification.state = MXKeyVerificationStateTransactionStarted;
    }
    else
    {
        MXKeyVerificationRequest *request = [self pendingRequestWithRequestId:keyVerificationId];
        if (request)
        {
            keyVerification = [MXKeyVerification new];
            keyVerification.request = request;
            keyVerification.state = MXKeyVerificationStateRequestPending;
        }
    }

    return keyVerification;
}


#pragma mark - SDK-Private methods -

+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        kMXKeyVerificationManagerDMEventTypes = @[
                                                    kMXEventTypeStringKeyVerificationReady,
                                                    kMXEventTypeStringKeyVerificationStart,
                                                    kMXEventTypeStringKeyVerificationAccept,
                                                    kMXEventTypeStringKeyVerificationKey,
                                                    kMXEventTypeStringKeyVerificationMac,
                                                    kMXEventTypeStringKeyVerificationCancel,
                                                    kMXEventTypeStringKeyVerificationDone
                                                    ];
    });
}

- (instancetype)initWithCrypto:(MXCrypto *)crypto
{
    self = [super init];
    if (self)
    {
        _crypto = crypto;
        cryptoQueue = self.crypto.cryptoQueue;

        transactions = [MXUsersDevicesMap new];

        // Observe incoming to-device events
        [self setupIncomingToDeviceEvents];

        // Observe incoming DM events
        [self setupIncomingDMEvents];

        _requestTimeout = MXRequestDefaultTimeout;
        pendingRequestsMap = [NSMutableDictionary dictionary];
        [self setupVericationByDMRequests];

        statusResolver = [[MXKeyVerificationStatusResolver alloc] initWithManager:self matrixSession:crypto.mxSession];
    }
    return self;
}

- (void)dealloc
{
    if (transactionTimeoutTimer)
    {
        [transactionTimeoutTimer invalidate];
        transactionTimeoutTimer = nil;
    }
}


#pragma mark - Requests

- (MXHTTPOperation*)sendToOtherInRequest:(MXKeyVerificationRequest*)request
                               eventType:(NSString*)eventType
                                 content:(NSDictionary*)content
                                 success:(dispatch_block_t)success
                                 failure:(void (^)(NSError *error))failure
{
    NSLog(@"[MXKeyVerification] sendToOtherInRequest: eventType: %@\n%@",
          eventType, content);
    
    MXHTTPOperation *operation;
    if ([request isKindOfClass:MXKeyVerificationByDMRequest.class])
    {
        MXKeyVerificationByDMRequest *requestByDM = (MXKeyVerificationByDMRequest*)request;
        operation = [self sendMessage:request.otherUser roomId:requestByDM.roomId eventType:eventType relatedTo:requestByDM.eventId content:content success:success failure:failure];
    }
    else
    {
        // Requests by to_device are not supported
        NSParameterAssert(NO);
    }
    
    return operation;
}

- (void)cancelVerificationRequest:(MXKeyVerificationRequest*)request
                          success:(void(^)(void))success
                          failure:(void(^)(NSError *error))failure
{
    MXTransactionCancelCode *cancelCode = MXTransactionCancelCode.user;

    // If there is transaction in progress, cancel it
    MXKeyVerificationTransaction *transaction = [self transactionWithTransactionId:request.requestId];
    if (transaction)
    {
        [self cancelTransaction:transaction code:cancelCode];
    }
    else
    {
        // Else only cancel the request
        MXKeyVerificationCancel *cancel = [MXKeyVerificationCancel new];
        cancel.transactionId = transaction.transactionId;
        cancel.code = cancelCode.value;
        cancel.reason = cancelCode.humanReadable;
        
        [self sendToOtherInRequest:request eventType:kMXEventTypeStringKeyVerificationCancel content:cancel.JSONDictionary success:success failure:failure];
    }
}


#pragma mark - Transactions

- (MXHTTPOperation*)sendToOtherInTransaction:(MXKeyVerificationTransaction*)transaction
                                   eventType:(NSString*)eventType
                                     content:(NSDictionary*)content
                                     success:(void (^)(void))success
                                     failure:(void (^)(NSError *error))failure
{
    NSLog(@"[MXKeyVerification] sendToOtherInTransaction%@: eventType: %@\n%@",
          transaction.dmEventId ? @"(DM)" : @"",
          eventType, content);

    MXHTTPOperation *operation;
    switch (transaction.transport)
    {
        case MKeyVerificationTransportToDevice:
            operation = [self sendToDevice:transaction.otherUserId deviceId:transaction.otherDeviceId eventType:eventType content:content success:success failure:failure];
            break;
        case MKeyVerificationTransportDirectMessage:
            operation = [self sendMessage:transaction.otherUserId roomId:transaction.dmRoomId eventType:eventType relatedTo:transaction.dmEventId content:content success:success failure:failure];
            break;
    }

    return operation;
}


- (void)cancelTransaction:(MXKeyVerificationTransaction*)transaction code:(MXTransactionCancelCode*)code
{
    NSLog(@"[MXKeyVerification] cancelTransaction. code: %@", code.value);
    
    MXKeyVerificationCancel *cancel = [MXKeyVerificationCancel new];
    cancel.transactionId = transaction.transactionId;
    cancel.code = code.value;
    cancel.reason = code.humanReadable;

    [self sendToOtherInTransaction:transaction eventType:kMXEventTypeStringKeyVerificationCancel content:cancel.JSONDictionary success:^{} failure:^(NSError *error) {

        NSLog(@"[MXKeyVerification] cancelTransaction. Error: %@", error);
    }];

    [self removeTransactionWithTransactionId:transaction.transactionId];
}

// Special handling for incoming requests that are not yet valid transactions
- (void)cancelTransactionFromStartEvent:(MXEvent*)event code:(MXTransactionCancelCode*)code
{
    NSLog(@"[MXKeyVerification] cancelTransactionFromStartEvent. code: %@", code.value);

    MXKeyVerificationStart *keyVerificationStart;
    MXJSONModelSetMXJSONModel(keyVerificationStart, MXKeyVerificationStart, event.content);

    if (keyVerificationStart)
    {
        MXKeyVerificationCancel *cancel = [MXKeyVerificationCancel new];
        cancel.transactionId = keyVerificationStart.transactionId;
        cancel.code = code.value;
        cancel.reason = code.humanReadable;

        // Which transport? DM or to_device events?
        if (keyVerificationStart.relatedEventId)
        {
            [self sendMessage:event.sender roomId:event.roomId eventType:kMXEventTypeStringKeyVerificationCancel relatedTo:keyVerificationStart.relatedEventId content:cancel.JSONDictionary success:nil failure:^(NSError *error) {

                NSLog(@"[MXKeyVerification] cancelTransactionFromStartEvent. Error: %@", error);
            }];
        }
        else
        {
            [self sendToDevice:event.sender deviceId:keyVerificationStart.fromDevice eventType:kMXEventTypeStringKeyVerificationCancel content:cancel.JSONDictionary success:nil failure:^(NSError *error) {

                NSLog(@"[MXKeyVerification] cancelTransactionFromStartEvent. Error: %@", error);
            }];
        }

        [self removeTransactionWithTransactionId:keyVerificationStart.transactionId];
    }
}


#pragma mark - Incoming events

- (void)handleKeyVerificationEvent:(MXEvent*)event
{
    NSLog(@"[MXKeyVerification] handleKeyVerificationEvent: eventType: %@\n%@", event.type, event.clearEvent.JSONDictionary);

    dispatch_async(cryptoQueue, ^{
        switch (event.eventType)
        {
            case MXEventTypeKeyVerificationReady:
                [self handleReadyEvent:event];
                break;
                
            case MXEventTypeKeyVerificationStart:
                [self handleStartEvent:event];
                break;

            case MXEventTypeKeyVerificationCancel:
                [self handleCancelEvent:event];
                break;

            case MXEventTypeKeyVerificationAccept:
                [self handleAcceptEvent:event];
                break;

            case MXEventTypeKeyVerificationKey:
                [self handleKeyEvent:event];
                break;

            case MXEventTypeKeyVerificationMac:
                [self handleMacEvent:event];
                break;

            default:
                break;
        }
    });
}

- (void)handleReadyEvent:(MXEvent*)event
{
    NSLog(@"[MXKeyVerification] handleReadyEvent");
    
    MXKeyVerificationReady *keyVerificationReady;
    MXJSONModelSetMXJSONModel(keyVerificationReady, MXKeyVerificationReady, event.content);
    
    if (!keyVerificationReady)
    {
        return;
    }
    
    NSString *requestId = keyVerificationReady.transactionId;
    MXKeyVerificationRequest *request = [self pendingRequestWithRequestId:requestId];
    if (request)
    {
        [request handleReady:keyVerificationReady];
    }
}
    
- (void)handleStartEvent:(MXEvent*)event
{
    NSLog(@"[MXKeyVerification] handleStartEvent");

    MXKeyVerificationStart *keyVerificationStart;
    MXJSONModelSetMXJSONModel(keyVerificationStart, MXKeyVerificationStart, event.content);

    if (!keyVerificationStart)
    {
        return;
    }

    NSString *requestId = keyVerificationStart.transactionId;
    MXKeyVerificationRequest *request = [self pendingRequestWithRequestId:requestId];
    if (request)
    {
        // The other party decided to create a transaction from the request
        // The request is complete
        [self removePendingRequestWithRequestId:request.requestId];
    }
    else if ([event.relatesTo.relationType isEqualToString:MXEventRelationTypeReference])
    {
        // This is a start response to a request we did not make. Ignore it
        NSLog(@"[MXKeyVerification] handleStartEvent: Start event for verification by DM(%@) not triggered by this device. Ignore it", requestId);
        return;
    }

    if (!keyVerificationStart.isValid)
    {
        if (keyVerificationStart.transactionId && keyVerificationStart.fromDevice)
        {
            [self cancelTransactionFromStartEvent:event code:MXTransactionCancelCode.invalidMessage];
        }

        return;
    }


    // Make sure we have other device keys
    [self loadDeviceWithDeviceId:keyVerificationStart.fromDevice andUserId:event.sender success:^(MXDeviceInfo *otherDevice) {

        MXKeyVerificationTransaction *existingTransaction = [self transactionWithUser:event.sender andDevice:keyVerificationStart.fromDevice];
        if (existingTransaction)
        {
            NSLog(@"[MXKeyVerification] handleStartEvent: already existing transaction. Cancel both");

            [existingTransaction cancelWithCancelCode:MXTransactionCancelCode.invalidMessage];
            [self cancelTransactionFromStartEvent:event code:MXTransactionCancelCode.invalidMessage];
            return;
        }

        // Multiple keyshares between two devices: any two devices may only have at most one key verification in flight at a time.
        NSArray<MXKeyVerificationTransaction*> *transactionsWithUser = [self transactionsWithUser:event.sender];
        if (transactionsWithUser.count)
        {
            NSLog(@"[MXKeyVerification] handleStartEvent: already existing transaction with the user. Cancel both");

            [transactionsWithUser[0] cancelWithCancelCode:MXTransactionCancelCode.invalidMessage];
            [self cancelTransactionFromStartEvent:event code:MXTransactionCancelCode.invalidMessage];
            return;
        }

        
        // We support only SAS at the moment
        MXIncomingSASTransaction *transaction = [[MXIncomingSASTransaction alloc] initWithOtherDevice:otherDevice startEvent:event andManager:self];
        if (transaction)
        {
            if ([self isCreationDateValid:transaction])
            {
                [self addTransaction:transaction];
                
                if (request)
                {
                    NSLog(@"[MXKeyVerification] handleStartEvent: auto accept incoming transaction in response of a request");
                    [transaction accept];
                }
            }
            else
            {
                NSLog(@"[MXKeyVerification] handleStartEvent: Expired transaction: %@", transaction);
                [self cancelTransactionFromStartEvent:event code:MXTransactionCancelCode.timeout];
            }
        }
        else
        {
            NSLog(@"[MXKeyVerification] handleStartEvent: Unsupported transaction method: %@", event);
            [self cancelTransactionFromStartEvent:event code:MXTransactionCancelCode.unknownMethod];
        }

    } failure:^(NSError *error) {
        NSLog(@"[MXKeyVerification] handleStartEvent: Failed to get other device keys: %@", event);
        [self cancelTransactionFromStartEvent:event code:MXTransactionCancelCode.invalidMessage];
    }];
}

- (void)handleCancelEvent:(MXEvent*)event
{
    NSLog(@"[MXKeyVerification] handleCancelEvent");

    MXKeyVerificationCancel *cancelContent;
    MXJSONModelSetMXJSONModel(cancelContent, MXKeyVerificationCancel, event.content);

    if (cancelContent)
    {
        MXKeyVerificationTransaction *transaction = [self transactionWithTransactionId:cancelContent.transactionId];
        if (transaction)
        {
            [transaction handleCancel:cancelContent];
            [self removeTransactionWithTransactionId:transaction.transactionId];
        }

        NSString *requestId = cancelContent.transactionId;
        MXKeyVerificationRequest *request = [self pendingRequestWithRequestId:requestId];
        if (request)
        {
            [request handleCancel:cancelContent];
        }
    }
    else
    {
        NSLog(@"[MXKeyVerification] handleCancelEvent. Invalid event: %@", event);
    }
}

- (void)handleAcceptEvent:(MXEvent*)event
{
    NSLog(@"[MXKeyVerification] handleAcceptEvent");

    MXKeyVerificationAccept *acceptContent;
    MXJSONModelSetMXJSONModel(acceptContent, MXKeyVerificationAccept, event.content);

    if (acceptContent)
    {
        MXKeyVerificationTransaction *transaction = [self transactionWithTransactionId:acceptContent.transactionId];
        if (transaction)
        {
            [transaction handleAccept:acceptContent];
        }
        else
        {
            NSLog(@"[MXKeyVerification] handleAcceptEvent. Unknown transaction: %@", event);
        }
    }
    else
    {
        NSLog(@"[MXKeyVerification] handleAcceptEvent. Invalid event: %@", event);
    }
}

- (void)handleKeyEvent:(MXEvent*)event
{
    NSLog(@"[MXKeyVerification] handleKeyEvent");

    MXKeyVerificationKey *keyContent;
    MXJSONModelSetMXJSONModel(keyContent, MXKeyVerificationKey, event.content);

    if (keyContent)
    {
        MXKeyVerificationTransaction *transaction = [self transactionWithTransactionId:keyContent.transactionId];
        if (transaction)
        {
            [transaction handleKey:keyContent];
        }
        else
        {
            NSLog(@"[MXKeyVerification] handleKeyEvent. Unknown transaction: %@", event);
        }
    }
    else
    {
        NSLog(@"[MXKeyVerification] handleKeyEvent. Invalid event: %@", event);
    }
}

- (void)handleMacEvent:(MXEvent*)event
{
    NSLog(@"[MXKeyVerification] handleMacEvent");

    MXKeyVerificationMac *macContent;
    MXJSONModelSetMXJSONModel(macContent, MXKeyVerificationMac, event.content);

    if (macContent)
    {
        MXKeyVerificationTransaction *transaction = [self transactionWithTransactionId:macContent.transactionId];
        if (transaction)
        {
            [transaction handleMac:macContent];
        }
        else
        {
            NSLog(@"[MXKeyVerification] handleMacEvent. Unknown transaction: %@", event);
        }
    }
    else
    {
        NSLog(@"[MXKeyVerification] handleMacEvent. Invalid event: %@", event);
    }
}


#pragma mark - Transport -
#pragma mark to_device

- (void)setupIncomingToDeviceEvents
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onToDeviceEvent:) name:kMXSessionOnToDeviceEventNotification object:_crypto.mxSession];
}

- (void)onToDeviceEvent:(NSNotification *)notification
{
    MXEvent *event = notification.userInfo[kMXSessionNotificationEventKey];
    [self handleKeyVerificationEvent:event];
}

- (MXHTTPOperation*)sendToDevice:(NSString*)userId
                        deviceId:(NSString*)deviceId
                       eventType:(NSString*)eventType
                         content:(NSDictionary*)content
                         success:(void (^)(void))success
                         failure:(void (^)(NSError *error))failure
{
    MXUsersDevicesMap<NSDictionary*> *contentMap = [[MXUsersDevicesMap alloc] init];
    [contentMap setObject:content forUser:userId andDevice:deviceId];

    return [self.crypto.matrixRestClient sendToDevice:eventType contentMap:contentMap txnId:nil success:success failure:failure];
}


#pragma mark DM

- (void)setupIncomingDMEvents
{
    [_crypto.mxSession listenToEventsOfTypes:kMXKeyVerificationManagerDMEventTypes onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
        if (direction == MXTimelineDirectionForwards
            && ![event.sender isEqualToString:self.crypto.mxSession.myUser.userId])
        {
            [self handleKeyVerificationEvent:event];
        }
    }];
}

- (BOOL)isVerificationByDMEventType:(MXEventTypeString)type
{
    return [kMXKeyVerificationManagerDMEventTypes containsObject:type];
}

- (MXHTTPOperation*)sendMessage:(NSString*)userId
                         roomId:(NSString*)roomId
                      eventType:(NSString*)eventType
                      relatedTo:(NSString*)relatedTo
                        content:(NSDictionary*)content
                        success:(void (^)(void))success
                        failure:(void (^)(NSError *error))failure
{
    NSMutableDictionary *eventContent = [content mutableCopy];

    eventContent[@"m.relates_to"] = @{
                                      @"rel_type": MXEventRelationTypeReference,
                                      @"event_id": relatedTo,
                                      };

    [eventContent removeObjectForKey:@"transaction_id"];

    return [self sendEventOfType:eventType toRoom:roomId content:eventContent success:^(NSString *eventId) {
        if (success)
        {
            success();
        }
    } failure:failure];
}

- (void)setupVericationByDMRequests
{
    NSArray *types = @[
                       kMXEventTypeStringRoomMessage
                       ];

    [_crypto.mxSession listenToEventsOfTypes:types onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
        if (direction == MXTimelineDirectionForwards
            && [event.content[@"msgtype"] isEqualToString:kMXMessageTypeKeyVerificationRequest])
        {
            MXKeyVerificationByDMRequest *requestByDM = [[MXKeyVerificationByDMRequest alloc] initWithEvent:event andManager:self];
            if (requestByDM)
            {
                [self handleKeyVerificationRequest:requestByDM event:event];
            }
        }
    }];
}


- (void)handleKeyVerificationRequest:(MXKeyVerificationRequest*)request event:(MXEvent*)event
{
    NSLog(@"[MXKeyVerification] handleKeyVerificationRequest: %@", request);

    if (![request.request.to isEqualToString:self.crypto.mxSession.myUser.userId])
    {
        NSLog(@"[MXKeyVerification] handleKeyVerificationRequest: Request for another user: %@", request.request.to);
        return;
    }

    MXWeakify(self);
    dispatch_async(dispatch_get_main_queue(), ^{
        MXStrongifyAndReturnIfNil(self);

        // This is a live event, we should have all data
        [self->statusResolver keyVerificationWithKeyVerificationId:request.requestId event:event transport:MKeyVerificationTransportDirectMessage success:^(MXKeyVerification * _Nonnull keyVerification) {

            if (keyVerification.request.state == MXKeyVerificationRequestStatePending)
            {
                [self addPendingRequest:request notify:YES];
            }

        } failure:^(NSError *error) {
            NSLog(@"[MXKeyVerificationRequest] handleKeyVerificationRequest: Failed to resolve state: %@", request.requestId);
        }];
    });
}



#pragma mark - Private methods -

- (void)loadDeviceWithDeviceId:(NSString*)deviceId
                     andUserId:(NSString*)userId
                       success:(void (^)(MXDeviceInfo *otherDevice))success
                       failure:(void (^)(NSError *error))failure
{
    MXWeakify(self);
    [_crypto downloadKeys:@[userId] forceDownload:NO success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
        MXStrongifyAndReturnIfNil(self);

        dispatch_async(self->cryptoQueue, ^{
            MXDeviceInfo *otherDevice = [usersDevicesInfoMap objectForDevice:deviceId forUser:userId];
            if (otherDevice)
            {
                success(otherDevice);
            }
            else
            {
                NSError *error = [NSError errorWithDomain:MXKeyVerificationErrorDomain
                                                     code:MXKeyVerificationUnknownDeviceCode
                                                 userInfo:@{
                                                            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown device: %@:%@", userId, deviceId]
                                                            }];
                failure(error);
            }
        });

    } failure:failure];
}

/**
 Send a message to a room even if it is e2e encrypted.
 This may require to mark unknown devices as known, which is legitimate because
 we are going to verify them or their user.
 */
- (MXHTTPOperation*)sendEventOfType:(MXEventTypeString)eventType
                             toRoom:(NSString*)roomId
                            content:(NSDictionary*)content
                            success:(void (^)(NSString *eventId))success
                            failure:(void (^)(NSError *error))failure
{
    // Check we have a room
    MXRoom *room = [_crypto.mxSession roomWithRoomId:roomId];
    if (!room)
    {
        NSError *error = [NSError errorWithDomain:MXKeyVerificationErrorDomain
                                             code:MXKeyVerificationUnknownRoomCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown room: %@", roomId]
                                                    }];
        if (failure)
        {
            failure(error);
        }
        return nil;
    }

    MXHTTPOperation *operation = [MXHTTPOperation new];
    operation = [room sendEventOfType:eventType content:content localEcho:nil success:success failure:^(NSError *error) {

        if ([error.domain isEqualToString:MXEncryptingErrorDomain] &&
            error.code == MXEncryptingErrorUnknownDeviceCode)
        {
            // Acknownledge unknown devices
            MXUsersDevicesMap<MXDeviceInfo *> *unknownDevices = error.userInfo[MXEncryptingErrorUnknownDeviceDevicesKey];
            [self.crypto setDevicesKnown:unknownDevices complete:^{
                // And retry
                MXHTTPOperation *operation2 = [room sendEventOfType:eventType content:content localEcho:nil success:success failure:failure];
                [operation mutateTo:operation2];
            }];
        }
        else if (failure)
        {
            failure(error);
        }
    }];

    return operation;
}


#pragma mark - Requests queue

- (nullable MXKeyVerificationByDMRequest*)verificationRequestInDMEvent:(MXEvent*)event
{
    MXKeyVerificationByDMRequest *request;
    if ([event.content[@"msgtype"] isEqualToString:kMXMessageTypeKeyVerificationRequest])
    {
        request = [[MXKeyVerificationByDMRequest alloc] initWithEvent:event andManager:self];
    }
    return request;
}

- (nullable MXKeyVerificationRequest*)pendingRequestWithRequestId:(NSString*)requestId
{
    return pendingRequestsMap[requestId];
}

- (void)addPendingRequest:(MXKeyVerificationRequest *)request notify:(BOOL)notify
{
    if (!pendingRequestsMap[request.requestId])
    {
        pendingRequestsMap[request.requestId] = request;

        if (notify)
        {
            [[NSNotificationCenter defaultCenter] postNotificationName:MXKeyVerificationManagerNewRequestNotification object:self userInfo:
             @{
               MXKeyVerificationManagerNotificationRequestKey: request
               }];
        }
    }
    [self scheduleRequestTimeoutTimer];
}

- (void)removePendingRequestWithRequestId:(NSString*)requestId
{
    if (pendingRequestsMap[requestId])
    {
        [pendingRequestsMap removeObjectForKey:requestId];
        [self scheduleRequestTimeoutTimer];
    }
}


#pragma mark - Timeout management

- (nullable NSDate*)oldestRequestDate
{
    NSDate *oldestRequestDate;
    for (MXKeyVerificationRequest *request in pendingRequestsMap.allValues)
    {
        if (!oldestRequestDate
            || request.ageLocalTs < oldestRequestDate.timeIntervalSince1970)
        {
            oldestRequestDate = [NSDate dateWithTimeIntervalSince1970:(request.ageLocalTs / 1000)];
        }
    }
    return oldestRequestDate;
}

- (BOOL)isRequestStillPending:(MXKeyVerificationRequest*)request
{
    NSDate *requestDate = [NSDate dateWithTimeIntervalSince1970:(request.ageLocalTs / 1000)];
    return (requestDate.timeIntervalSinceNow > -_requestTimeout);
}

- (void)scheduleRequestTimeoutTimer
{
    if (requestTimeoutTimer)
    {
        if (!pendingRequestsMap.count)
        {
            NSLog(@"[MXKeyVerificationRequest] scheduleTimeoutTimer: Disable timer as there is no more requests");
            [requestTimeoutTimer invalidate];
            requestTimeoutTimer = nil;
        }

        return;
    }

    NSDate *oldestRequestDate = [self oldestRequestDate];
    if (oldestRequestDate)
    {
        NSLog(@"[MXKeyVerificationRequest] scheduleTimeoutTimer: Create timer");

        NSDate *timeoutDate = [oldestRequestDate dateByAddingTimeInterval:self.requestTimeout];
        self->requestTimeoutTimer = [[NSTimer alloc] initWithFireDate:timeoutDate
                                                      interval:0
                                                        target:self
                                                      selector:@selector(onRequestTimeoutTimer)
                                                      userInfo:nil
                                                       repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:self->requestTimeoutTimer forMode:NSDefaultRunLoopMode];
    }
}

- (void)onRequestTimeoutTimer
{
    NSLog(@"[MXKeyVerificationRequest] onTimeoutTimer");
    requestTimeoutTimer = nil;

    [self checkRequestTimeouts];
    [self scheduleRequestTimeoutTimer];
}

- (void)checkRequestTimeouts
{
    for (MXKeyVerificationRequest *request in pendingRequestsMap.allValues)
    {
        if ([self isRequestStillPending:request])
        {
            NSLog(@"[MXKeyVerificationRequest] checkTimeouts: timeout %@", request);
            [request cancelWithCancelCode:MXTransactionCancelCode.timeout success:nil failure:nil];
        }
    }
}


#pragma mark - Transactions queue

- (MXKeyVerificationTransaction*)transactionWithUser:(NSString*)userId andDevice:(NSString*)deviceId
{
    return [transactions objectForDevice:deviceId forUser:userId];
}

- (NSArray<MXKeyVerificationTransaction*>*)transactionsWithUser:(NSString*)userId
{
    return [transactions objectsForUser:userId];
}

- (MXKeyVerificationTransaction*)transactionWithTransactionId:(NSString*)transactionId
{
    MXKeyVerificationTransaction *transaction;
    for (MXKeyVerificationTransaction *t in transactions.allObjects)
    {
        if ([t.transactionId isEqualToString:transactionId])
        {
            transaction = t;
            break;
        }
    }

    return transaction;
}

- (void)addTransaction:(MXKeyVerificationTransaction*)transaction
{
    [transactions setObject:transaction forUser:transaction.otherUserId andDevice:transaction.otherDeviceId];
    [self scheduleTransactionTimeoutTimer];

    dispatch_async(dispatch_get_main_queue(),^{
        [[NSNotificationCenter defaultCenter] postNotificationName:MXKeyVerificationManagerNewTransactionNotification object:self userInfo:
         @{
           MXKeyVerificationManagerNotificationTransactionKey: transaction
           }];
    });
}

- (void)removeTransactionWithTransactionId:(NSString*)transactionId
{
    MXKeyVerificationTransaction *transaction = [self transactionWithTransactionId:transactionId];
    if (transaction)
    {
        [transactions removeObjectForUser:transaction.otherUserId andDevice:transaction.otherDeviceId];
        [self scheduleTransactionTimeoutTimer];
    }
}

- (nullable NSDate*)oldestTransactionCreationDate
{
    NSDate *oldestCreationDate;
    for (MXKeyVerificationTransaction *transaction in transactions.allObjects)
    {
        if (!oldestCreationDate
            || transaction.creationDate.timeIntervalSince1970 < oldestCreationDate.timeIntervalSince1970)
        {
            oldestCreationDate = transaction.creationDate;
        }
    }
    return oldestCreationDate;
}

- (BOOL)isCreationDateValid:(MXKeyVerificationTransaction*)transaction
{
    return (transaction.creationDate.timeIntervalSinceNow > -MXTransactionTimeout);
}


#pragma mark Timeout management

- (void)scheduleTransactionTimeoutTimer
{
    if (transactionTimeoutTimer)
    {
        if (!transactions.count)
        {
            NSLog(@"[MXKeyVerification] scheduleTimeoutTimer: Disable timer as there is no more transactions");
            [transactionTimeoutTimer invalidate];
            transactionTimeoutTimer = nil;
        }

        return;
    }

    NSDate *oldestCreationDate = [self oldestTransactionCreationDate];
    if (oldestCreationDate)
    {
        MXWeakify(self);
        dispatch_async(dispatch_get_main_queue(), ^{
            MXStrongifyAndReturnIfNil(self);

            if (self->transactionTimeoutTimer)
            {
                return;
            }

            NSLog(@"[MXKeyVerification] scheduleTimeoutTimer: Create timer");

            NSDate *timeoutDate = [oldestCreationDate dateByAddingTimeInterval:MXTransactionTimeout];
            self->transactionTimeoutTimer = [[NSTimer alloc] initWithFireDate:timeoutDate
                                                          interval:0
                                                            target:self
                                                          selector:@selector(onTransactionTimeoutTimer)
                                                          userInfo:nil
                                                           repeats:NO];
            [[NSRunLoop mainRunLoop] addTimer:self->transactionTimeoutTimer forMode:NSDefaultRunLoopMode];
        });
    }
}

- (void)onTransactionTimeoutTimer
{
    NSLog(@"[MXKeyVerification] onTimeoutTimer");
    self->transactionTimeoutTimer = nil;

    if (cryptoQueue)
    {
        dispatch_async(cryptoQueue, ^{
            [self checkTransactionTimeouts];
            [self scheduleTransactionTimeoutTimer];
        });
    }
}

- (void)checkTransactionTimeouts
{
    for (MXKeyVerificationTransaction *transaction in transactions.allObjects)
    {
        if (![self isCreationDateValid:transaction])
        {
            NSLog(@"[MXKeyVerification] checkTimeouts: timeout %@", transaction);
            [transaction cancelWithCancelCode:MXTransactionCancelCode.timeout];
        }
    }
}

@end

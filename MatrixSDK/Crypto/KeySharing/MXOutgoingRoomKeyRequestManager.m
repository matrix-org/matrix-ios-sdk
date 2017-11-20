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

#import "MXOutgoingRoomKeyRequestManager.h"

#import "MXTools.h"
#import "MXOutgoingRoomKeyRequest.h"

#ifdef MX_CRYPTO

// delay between deciding we want some keys, and sending out the request, to
// allow for (a) it turning up anyway, (b) grouping requests together
NSUInteger const SEND_KEY_REQUESTS_DELAY_MS = 500;


@interface MXOutgoingRoomKeyRequestManager ()
{
    MXRestClient *matrixRestClient;
    NSString *deviceId;
    dispatch_queue_t cryptoQueue;
    id<MXCryptoStore> cryptoStore;

    // handle for the delayed call to sendOutgoingRoomKeyRequests. Non-null
    // if the callback has been set, or if it is still running.
    NSTimer *sendOutgoingRoomKeyRequestsTimer;
}
@end

@implementation MXOutgoingRoomKeyRequestManager

- (id)initWithMatrixRestClient:(MXRestClient*)mxRestClient
                      deviceId:(NSString*)theDeviceId
                   cryptoQueue:(dispatch_queue_t)theCryptoQueue
                   cryptoStore:(id<MXCryptoStore>)theCryptoStore
{
    self = [super init];
    if (self)
    {
        matrixRestClient = mxRestClient;
        deviceId = theDeviceId;
        cryptoQueue = theCryptoQueue;
        cryptoStore = theCryptoStore;
    }
    return self;
}

- (void)start
{
    // set the timer going, to handle any requests which didn't get sent
    // on the previous run of the client.
    [self startTimer];
}

- (void)close
{
    // Close is planned to be called from the main thread
    NSParameterAssert([NSThread isMainThread]);

    [sendOutgoingRoomKeyRequestsTimer invalidate];
    sendOutgoingRoomKeyRequestsTimer = nil;
}

- (void)sendRoomKeyRequest:(NSDictionary *)requestBody recipients:(NSArray<NSDictionary<NSString *,NSString *> *> *)recipients
{
    MXOutgoingRoomKeyRequest *request = [self getOrAddOutgoingRoomKeyRequest:requestBody recipients:recipients];

    if (request.state == MXRoomKeyRequestStateUnsent)
    {
        [self startTimer];
    }
}

- (void)cancelRoomKeyRequest:(NSDictionary *)requestBody
{
    MXOutgoingRoomKeyRequest *request = [cryptoStore outgoingRoomKeyRequestWithRequestBody:requestBody];
    if (!request)
    {
        // no request was made for this key
        return;
    }

    switch (request.state)
    {
        case MXRoomKeyRequestStateCancellationPending:
            // nothing to do here
            break;

        case MXRoomKeyRequestStateUnsent:
            // just delete it

            // FIXME: ghahah we may have attempted to send it, and
            // not yet got a successful response. So the server
            // may have seen it, so we still need to send a cancellation
            // in that case :/

            NSLog(@"[MXOutgoingRoomKeyRequestManager] cancelRoomKeyRequest: deleting unnecessary room key request for %@", requestBody);

            [cryptoStore deleteOutgoingRoomKeyRequestWithRequestId:request.requestId];
            break;

        case MXRoomKeyRequestStateSent:
            // send a cancellation.
            request.state = MXRoomKeyRequestStateCancellationPending;
            request.cancellationTxnId = [MXTools generateTransactionId];

            [cryptoStore updateOutgoingRoomKeyRequest:request];

            // We don't want to wait for the timer, so we send it
            // immediately. (We might actually end up racing with the timer,
            // but that's ok: even if we make the request twice, we'll do it
            // with the same transaction_id, so only one message will get
            // sent).
            //
            // (We also don't want to wait for the response from the server
            // here, as it will slow down processing of received keys if we
            // do.)
            __weak typeof(self) weakSelf = self;
            [self sendOutgoingRoomKeyRequestCancellation:request success:nil failure:^(NSError *error) {

                if (weakSelf)
                {
                    typeof(self) self = weakSelf;

                    NSLog(@"[MXOutgoingRoomKeyRequestManager] cancelRoomKeyRequest: Error sending room key request cancellation; will retry later.");

                    [self startTimer];
                }
            }];
    }

}

#pragma mark - Private methods

- (void)startTimer
{
    __weak typeof(self) weakSelf = self;

    // Must be called on the crypto thread
    // So, move on the main thread to create NSTimer
    dispatch_async(dispatch_get_main_queue(), ^{

        if (weakSelf)
        {
            typeof(self) self = weakSelf;

            if (self->sendOutgoingRoomKeyRequestsTimer)
            {
                return;
            }

            // Start expiration timer
            self->sendOutgoingRoomKeyRequestsTimer = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:SEND_KEY_REQUESTS_DELAY_MS / 1000.0]
                                                                              interval:0
                                                                                target:self
                                                                              selector:@selector(sendOutgoingRoomKeyRequests)
                                                                              userInfo:nil
                                                                               repeats:NO];
            [[NSRunLoop mainRunLoop] addTimer:self->sendOutgoingRoomKeyRequestsTimer forMode:NSDefaultRunLoopMode];
        }
    });
}

- (void)sendOutgoingRoomKeyRequests
{
    NSLog(@"[MXOutgoingRoomKeyRequestManager] startSendingOutgoingRoomKeyRequests: Looking for queued outgoing room key requests.");

    sendOutgoingRoomKeyRequestsTimer = nil;

    __weak typeof(self) weakSelf = self;

    // This method is called on the [NSRunLoop mainRunLoop]. Go to the crypto thread
    dispatch_async(cryptoQueue, ^{

        if (!weakSelf)
        {
            return;
        }

        typeof(self) self = weakSelf;

        MXOutgoingRoomKeyRequest* request = [self->cryptoStore outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateCancellationPending];
        if (!request)
        {
            request = [self->cryptoStore outgoingRoomKeyRequestWithState:MXRoomKeyRequestStateUnsent];
        }

        if (!request)
        {
            NSLog(@"[MXOutgoingRoomKeyRequestManager] startSendingOutgoingRoomKeyRequests: No more outgoing room key requests");
            return;
        }

        void(^onSuccess)() = ^(NSString *eventId) {
            if (weakSelf)
            {
                typeof(self) self = weakSelf;

                // go around the loop again
                [self sendOutgoingRoomKeyRequests];
            }
        };

        void(^onFailure)(NSError *) = ^(NSError *error) {
            if (weakSelf)
            {
                typeof(self) self = weakSelf;
                NSLog(@"[MXOutgoingRoomKeyRequestManager] startSendingOutgoingRoomKeyRequests: Error sending room key request; will retry later");

                [self startTimer];
            }
        };

        if (request.state == MXRoomKeyRequestStateUnsent)
        {
            [self sendOutgoingRoomKeyRequest:request success:onSuccess failure:onFailure];
        }
        else
        {
            // must be a cancellation
            [self sendOutgoingRoomKeyRequestCancellation:request success:onSuccess failure:onFailure];
        }
    });
}

// given a RoomKeyRequest, send it and update the request record
- (void)sendOutgoingRoomKeyRequest:(MXOutgoingRoomKeyRequest*)request
                           success:(void (^)())success
                           failure:(void (^)(NSError *error))failure
{
    NSLog(@"[MXOutgoingRoomKeyRequestManager] Requesting keys for %@ from %@ (id %@)", request.requestBody, request.recipients, request.requestId);

    NSDictionary *requestMessage = @{
                                     @"action": @"request",
                                     @"requesting_device_id": deviceId,
                                     @"request_id": request.requestId,
                                     @"body": request.requestBody
                                     };

     __weak typeof(self) weakSelf = self;
    [self sendMessageToDevices:requestMessage recipients:request.recipients txnId:request.requestId success:^{
        if (weakSelf)
        {
            request.state = MXRoomKeyRequestStateSent;
            [self->cryptoStore updateOutgoingRoomKeyRequest:request];

            success();
        }
    } failure:failure];
}

// given a RoomKeyRequest, cancel it and delete the request record
- (void)sendOutgoingRoomKeyRequestCancellation:(MXOutgoingRoomKeyRequest*)request
                                       success:(void (^)())success
                                       failure:(void (^)(NSError *error))failure
{
    NSLog(@"[MXOutgoingRoomKeyRequestManager] Sending cancellation for key request for %@ from %@ (cancellation id %@)", request.requestBody, request.recipients, request.cancellationTxnId);

    NSDictionary *requestMessage = @{
                                     @"action": @"request_cancellation",
                                     @"requesting_device_id": deviceId,
                                     @"request_id": request.requestId
                                     };

    __weak typeof(self) weakSelf = self;
    [self sendMessageToDevices:requestMessage recipients:request.recipients txnId:request.cancellationTxnId success:^{
        if (weakSelf)
        {
            [self->cryptoStore deleteOutgoingRoomKeyRequestWithRequestId:request.requestId];

            success();
        }
    } failure:failure];
}

- (void)sendMessageToDevices:(NSDictionary*)message
                  recipients:(NSArray<NSDictionary<NSString *,NSString *> *> *)recipients
                       txnId:(NSString*)txnId
                     success:(void (^)())success
                     failure:(void (^)(NSError *error))failure
{
    MXUsersDevicesMap<NSDictionary*> *contentMap = [[MXUsersDevicesMap alloc] init];
    for (NSDictionary<NSString *,NSString *> *recipient in recipients)
    {
        [contentMap setObject:message forUser:recipient[@"userId"] andDevice:recipient[@"deviceId"]];
    }

    [matrixRestClient sendToDevice:kMXEventTypeStringRoomKeyRequest contentMap:contentMap txnId:txnId success:success failure:failure];
}

/**
 Look for an existing outgoing room key request, and if none is found,
 add a new one

 @param requestBody the body of the request.
 @param recipients the recipients.
 @returns the existing outgoing room key request or a new one.
 */
- (MXOutgoingRoomKeyRequest*)getOrAddOutgoingRoomKeyRequest:(NSDictionary *)requestBody
                                                 recipients:(NSArray<NSDictionary<NSString *,NSString *> *> *)recipients
{
    // first see if we already have an entry for this request.
    MXOutgoingRoomKeyRequest *outgoingRoomKeyRequest = [cryptoStore outgoingRoomKeyRequestWithRequestBody:requestBody];
    if (outgoingRoomKeyRequest)
    {
        // this entry matches the request - return it.
        NSLog(@"[MXOutgoingRoomKeyRequestManager] getOrAddOutgoingRoomKeyRequest: already have key request outstanding for %@ / %@: not sending another", requestBody[@"room_id"], requestBody[@"session_id"]);
        return outgoingRoomKeyRequest;
    }

    // we got to the end of the list without finding a match
    // - add the new request.
    NSLog(@"[MXOutgoingRoomKeyRequestManager] getOrAddOutgoingRoomKeyRequest: enqueueing key request for for %@ / %@", requestBody[@"room_id"], requestBody[@"session_id"]);

    outgoingRoomKeyRequest = [[MXOutgoingRoomKeyRequest alloc] init];
    outgoingRoomKeyRequest.requestBody = requestBody;
    outgoingRoomKeyRequest.recipients = recipients;
    outgoingRoomKeyRequest.requestId = [MXTools generateTransactionId];
    outgoingRoomKeyRequest.state = MXRoomKeyRequestStateUnsent;

    [cryptoStore storeOutgoingRoomKeyRequest:outgoingRoomKeyRequest];

    return outgoingRoomKeyRequest;
}

@end

#endif

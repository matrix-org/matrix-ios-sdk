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

#import "MXKeyVerificationRequest_Private.h"

#import "MXKeyVerificationManager_Private.h"

#import "MXCrypto_Private.h"


#pragma mark - Constants
NSString * const MXKeyVerificationRequestDidChangeNotification = @"MXKeyVerificationRequestDidChangeNotification";

@interface MXKeyVerificationRequest()

@property (nonatomic, readwrite) MXKeyVerificationRequestState state;

@end

@implementation MXKeyVerificationRequest

#pragma mark - SDK-Private methods -

- (instancetype)initWithEvent:(MXEvent*)event andManager:(MXKeyVerificationManager*)manager
{
    // Check verification by DM request format
    MXKeyVerificationRequestJSONModel *request;
    MXJSONModelSetMXJSONModel(request, MXKeyVerificationRequestJSONModel.class, event.content);
    
    if (!request)
    {
        return nil;
    }
    
    self = [super init];
    if (self)
    {
        _event = event;
        _request = request;
        _state = MXKeyVerificationRequestStatePending;
        _manager = manager;
    }
    return self;
}

- (void)acceptWithMethods:(NSArray<NSString *> *)methods success:(dispatch_block_t)success failure:(void (^)(NSError * _Nonnull))failure
{
    NSString *myDeviceId = self.manager.crypto.mxSession.matrixRestClient.credentials.deviceId;
    
    MXKeyVerificationReady *ready = [MXKeyVerificationReady new];
    ready.transactionId = self.requestId;
    ready.relatedEventId = _event.eventId;
    ready.methods = methods;
    ready.fromDevice = myDeviceId;

    [self.manager sendToOtherInRequest:self eventType:kMXEventTypeStringKeyVerificationReady content:ready.JSONDictionary success:^{
        self.acceptedData = ready;
        [self updateState:MXKeyVerificationRequestStateAccepted notifiy:YES];

        success();
    }  failure:failure];
}

- (void)cancelWithCancelCode:(MXTransactionCancelCode*)code success:(void(^)(void))success failure:(void(^)(NSError *error))failure
{
    [self.manager cancelVerificationRequest:self success:^{
        self.reasonCancelCode = code;
        
        [self updateState:MXKeyVerificationRequestStateCancelledByMe notifiy:YES];
        [self.manager removePendingRequestWithRequestId:self.requestId];
        
        if (success)
        {
            success();
        }
        
    } failure:failure];
}

- (void)updateState:(MXKeyVerificationRequestState)state notifiy:(BOOL)notify
{
    if (state == self.state)
    {
        return;
    }
    
    self.state = state;
    
    if (notify)
    {
        [self didUpdateState];
    }
}

- (void)didUpdateState
{
    dispatch_async(dispatch_get_main_queue(),^{
        [[NSNotificationCenter defaultCenter] postNotificationName:MXKeyVerificationRequestDidChangeNotification object:self userInfo:nil];
    });
}

- (void)handleReady:(MXKeyVerificationReady*)readyContent
{
    self.acceptedData = readyContent;
    [self updateState:MXKeyVerificationRequestStateAccepted notifiy:YES];
}

- (void)handleCancel:(MXKeyVerificationCancel *)cancelContent
{
    self.reasonCancelCode = [[MXTransactionCancelCode alloc] initWithValue:cancelContent.code
                                                             humanReadable:cancelContent.reason];
    
    [self updateState:MXKeyVerificationRequestStateCancelled notifiy:YES];
    [self.manager removePendingRequestWithRequestId:self.requestId];
}

// Shortcuts
- (NSString *)requestId
{
    return _event.eventId;
}

- (uint64_t)ageLocalTs
{
    return _event.ageLocalTs;
}


// Shortcuts to the original request
- (NSString *)to
{
    return _request.to;
}

- (NSString *)otherUser
{
    return _isFromMyUser ? _request.to : _event.sender;
}

- (NSString *)otherDevice
{
    return _isFromMyUser ? _acceptedData.fromDevice : _request.fromDevice;
}

- (NSString *)fromDevice
{
    return _request.fromDevice;
}

- (NSArray<NSString *> *)methods
{
    return _request.methods;
}


// Shortcuts to the accepted event
-(NSArray<NSString *> *)acceptedMethods
{
    return _acceptedData.methods;
}


// Shortcuts of methods according to the point of view
- (NSArray<NSString *> *)myMethods
{
    return _isFromMyUser ? self.methods : self.acceptedMethods;
}

- (NSArray<NSString *> *)otherMethods
{
    return _isFromMyUser ? self.acceptedMethods : self.methods;
}

@end

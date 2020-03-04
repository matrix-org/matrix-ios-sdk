/*
 Copyright 2020 The Matrix.org Foundation C.I.C
 
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

#import "MXSecretShareManager_Private.h"

#import "MXCrypto_Private.h"
#import "MXSecretShareRequest.h"
#import "MXSecretShareSend.h"
#import "MXTools.h"

static NSArray<MXEventTypeString> *kMXSecretShareEventTypes;


@interface MXSecretShareManager ()

@property (nonatomic, readonly, weak) MXCrypto *crypto;

@end


@implementation MXSecretShareManager

- (MXHTTPOperation *)requestSecret:(NSString*)secretId
                       toDeviceIds:(nullable NSArray<NSString*>*)deviceIds
                           success:(void (^)(NSString *requestId))success
                  onSecretReceived:(void (^)(NSString *secret))onSecretReceived
                           failure:(void (^)(NSError *error))failure
{
    MXCredentials *myUser = _crypto.mxSession.matrixRestClient.credentials;
    
    MXSecretShareRequest *request = [MXSecretShareRequest new];
    request.name = secretId;
    request.action = MXSecretShareRequestAction.request;
    request.requestingDeviceId = myUser.deviceId;
    request.requestId = [MXTools generateTransactionId];
    
    // TODO: store it permanently?
    // Probably no
    
    NSDictionary *requestContent = request.JSONDictionary;
    
    MXUsersDevicesMap<NSDictionary*> *contentMap = [[MXUsersDevicesMap alloc] init];
    if (deviceIds)
    {
        for (NSString *deviceId in deviceIds)
        {
            [contentMap setObject:requestContent forUser:myUser.userId andDevice:deviceId];
        }
    }
    else
    {
        [contentMap setObject:requestContent forUser:myUser.userId andDevice:@"*"];
    }

    
    return [_crypto.matrixRestClient sendToDevice:kMXEventTypeStringSecretRequest contentMap:contentMap txnId:request.requestId success:^{
        
        dispatch_async(dispatch_get_main_queue(), ^{
            success(request.requestId);
        });
        
        // TODO: Implement onSecretReceived

    } failure:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            failure(error);
        });
    }];
}


#pragma mark - SDK-Private methods -

+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        kMXSecretShareEventTypes = @[
                                     kMXEventTypeStringSecretRequest,
                                     kMXEventTypeStringSecretSend
                                     ];
    });
}

- (instancetype)initWithCrypto:(MXCrypto *)crypto;
{
    self = [super init];
    if (self)
    {
        _crypto = crypto;
        
        // Observe incoming secret share requests
        [self setupIncomingRequests];
    }
    return self;
}


#pragma mark - Private methods -

- (BOOL)isSecretShareEvent:(MXEventTypeString)type
{
    return [kMXSecretShareEventTypes containsObject:type];
}

- (void)setupIncomingRequests
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onToDeviceEvent:) name:kMXSessionOnToDeviceEventNotification object:_crypto.mxSession];
}

- (void)onToDeviceEvent:(NSNotification *)notification
{
    MXEvent *event = notification.userInfo[kMXSessionNotificationEventKey];

    if ([self isSecretShareEvent:event.type])
    {
        [self handleSecretShareEvent:event];
    }
}

- (void)handleSecretShareEvent:(MXEvent*)event
{
    NSLog(@"[MXSecretShareManager] handleSecretShareEvent: eventType: %@", event.type);
    
    dispatch_async(_crypto.cryptoQueue, ^{
        switch (event.eventType)
        {
            case MXEventTypeSecretRequest:
                [self handleSecretRequestEvent:event];
                break;
                
            case MXEventTypeSecretSend:
                [self handleSecretSendtEvent:event];
                break;
                
            default:
                break;
        }
    });
}

- (void)handleSecretRequestEvent:(MXEvent*)event
{
    // TODO
}

- (void)handleSecretSendtEvent:(MXEvent*)event
{
      // TODO
}

@end

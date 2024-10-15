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

#import "MXPushGatewayRestClient.h"

#import <AFNetworking/AFNetworking.h>

#import "MXError.h"
#import "MXTools.h"
#import "MXBase64Tools.h"

static const char * const kMXPushGatewayRestClientProcessingQueueLabel = "MXPushGatewayRestClient";

@interface MXPushGatewayRestClient ()

/**
 HTTP client to the push gateway.
 */
@property (nonatomic, strong) MXHTTPClient *httpClient;

/**
 The queue to process server response.
 This queue is used to create models from JSON dictionary without blocking the main thread.
 */
@property (nonatomic) dispatch_queue_t processingQueue;

@end

@implementation MXPushGatewayRestClient

#pragma mark - Setup

- (instancetype)initWithPushGateway:(NSString * _Nonnull)pushGateway
  andOnUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock
{
    self = [super init];
    if (self)
    {
        _pushGateway = pushGateway;
        self.httpClient = [[MXHTTPClient alloc] initWithBaseURL:pushGateway
                              andOnUnrecognizedCertificateBlock:onUnrecognizedCertBlock];
        self.httpClient.requestParametersInJSON = YES;

        self.processingQueue = dispatch_queue_create(kMXPushGatewayRestClientProcessingQueueLabel, DISPATCH_QUEUE_SERIAL);
        self.completionQueue = dispatch_get_main_queue();
    }
    return self;
}

#pragma mark - Notify

- (MXHTTPOperation *)notifyAppWithId:(NSString * _Nonnull)appId
                           pushToken:(NSData * _Nonnull)pushToken
                             eventId:(nullable NSString *)eventId
                              roomId:(nullable NSString *)roomId
                           eventType:(nullable NSString *)eventType
                              sender:(nullable NSString *)sender
                             timeout:(NSTimeInterval)timeout
                             success:(void (^)(NSArray<NSString*> * _Nonnull))success
                             failure:(void (^)(NSError * _Nonnull))failure
{
    NSDictionary *device = @{
        @"app_id": appId,
        @"pushkey": [pushToken base64EncodedStringWithOptions:0]
    };
    
    NSMutableDictionary *notification = [@{
        @"devices": @[device]
    } mutableCopy];
    
    if (eventId)
    {
        notification[@"event_id"] = eventId;
    }
    if (roomId)
    {
        notification[@"room_id"] = roomId;
    }
    if (eventType)
    {
        notification[@"type"] = eventType;
    }
    if (sender)
    {
        notification[@"sender"] = sender;
    }
    
    NSDictionary *parameters = @{
        @"notification": notification
    };
    
    self.httpClient.acceptableContentTypes = [NSSet setWithObjects:@"text/html", @"application/json", nil];
    
    MXHTTPOperation *operation= [self.httpClient requestWithMethod:@"POST"
                                                              path:@"/_matrix/push/v1/notify"
                                                        parameters:parameters
                                                           timeout:timeout
                                                           success:^(NSDictionary *JSONResponse) {
        if (success)
        {
            __block NSArray<NSString*> *rejectedTokens;
            [self dispatchProcessing:^{
                MXJSONModelSetArray(rejectedTokens, JSONResponse[@"rejected"]);
            } andCompletion:^{
                success(rejectedTokens);
            }];
        }
    } failure:^(NSError *error) {
        [self dispatchFailure:error inBlock:failure];
    }];
    
    operation.maxNumberOfTries = 0;
    
    return operation;
}

#pragma mark - Private methods

/**
 Dispatch code blocks to respective GCD queue.
 
 @param processingBlock code block to run on the processing queue.
 @param completionBlock code block to run on the completion queue.
 */
- (void)dispatchProcessing:(dispatch_block_t)processingBlock andCompletion:(dispatch_block_t)completionBlock
{
    if (self.processingQueue)
    {
        MXWeakify(self);
        dispatch_async(self.processingQueue, ^{
            MXStrongifyAndReturnIfNil(self);
            
            if (processingBlock)
            {
                processingBlock();
            }
            
            if (self.completionQueue)
            {
                dispatch_async(self.completionQueue, ^{
                    completionBlock();
                });
            }
        });
    }
}

/**
 Dispatch the execution of the success block on the completion queue.
 
 with a go through the processing queue in order to keep the server
 response order.
 
 @param successBlock code block to run on the completion queue.
 */
- (void)dispatchSuccess:(dispatch_block_t)successBlock
{
    if (successBlock)
    {
        [self dispatchProcessing:nil andCompletion:successBlock];
    }
}

/**
 Dispatch the execution of the failure block on the completion queue.
 
 with a go through the processing queue in order to keep the server
 response order.
 
 @param failureBlock code block to run on the completion queue.
 */
- (void)dispatchFailure:(NSError*)error inBlock:(void (^)(NSError *error))failureBlock
{
    if (failureBlock && self.processingQueue)
    {
        MXWeakify(self);
        dispatch_async(self.processingQueue, ^{
            MXStrongifyAndReturnIfNil(self);
            
            if (self.completionQueue)
            {
                dispatch_async(self.completionQueue, ^{
                    failureBlock(error);
                });
            }
        });
    }
}

@end

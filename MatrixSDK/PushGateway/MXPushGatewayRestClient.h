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

#import <Foundation/Foundation.h>

#import "MXHTTPClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface MXPushGatewayRestClient : NSObject

/**
 The push gateway URL.
 */
@property (nonatomic, readonly) NSString *pushGateway;

/**
 The queue on which asynchronous response blocks are called.
 Default is dispatch_get_main_queue().
*/
@property (nonatomic, strong) dispatch_queue_t completionQueue;

/**
 Create an instance based on push gateway URL.

 @param pushGateway the push gateway URL.
 @param onUnrecognizedCertBlock the block called to handle unrecognized certificate (nil if unrecognized certificates are ignored).
 @return an MXPushGatewayRestClient instance.
*/
- (instancetype)initWithPushGateway:(NSString *)pushGateway
  andOnUnrecognizedCertificateBlock:(nullable MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock;

#pragma mark - Notify

/**
 Notify the given device.
 @param appId The application id
 @param pushToken The push token of the pusher
 @param eventId event id
 @param roomId room id
 @param eventType event type
 @param success A block object called when the operation succeeds. It provides the user access token for the identity server.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation *)notifyAppWithId:(NSString *)appId
                           pushToken:(NSData *)pushToken
                             eventId:(NSString *)eventId
                              roomId:(NSString *)roomId
                           eventType:(NSString *)eventType
                             success:(void (^)(NSArray<NSString*> * _Nonnull))success
                             failure:(void (^)(NSError * _Nonnull))failure;

@end

NS_ASSUME_NONNULL_END

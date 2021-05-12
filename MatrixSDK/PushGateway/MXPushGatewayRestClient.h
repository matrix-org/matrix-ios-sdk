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
- (instancetype)initWithPushGateway:(NSString * _Nonnull)pushGateway
  andOnUnrecognizedCertificateBlock:(nullable MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock;

#pragma mark - Notify

/**
 Notify the given device.
 @param appId The application id
 @param pushToken The push token of the pusher
 @param eventId event id
 @param roomId room id
 @param eventType event type
 @param sender sender of the event
 @param timeout client timeout for the operation. In seconds. Pass -1 to use the default value
 @param success A block object called when the operation succeeds. It provides the rejected tokens.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation *)notifyAppWithId:(NSString * _Nonnull)appId
                           pushToken:(NSData * _Nonnull)pushToken
                             eventId:(nullable NSString *)eventId
                              roomId:(nullable NSString *)roomId
                           eventType:(nullable NSString *)eventType
                              sender:(nullable NSString *)sender
                             timeout:(NSTimeInterval)timeout
                             success:(void (^)(NSArray<NSString*> * _Nonnull))success
                             failure:(void (^)(NSError * _Nonnull))failure;

@end

NS_ASSUME_NONNULL_END

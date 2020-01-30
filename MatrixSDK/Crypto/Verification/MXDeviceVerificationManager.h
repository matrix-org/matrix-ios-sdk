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

#import <Foundation/Foundation.h>

#import "MXKeyVerificationRequest.h"
#import "MXDeviceVerificationTransaction.h"
#import "MXKeyVerification.h"

#import "MXSASTransaction.h"
#import "MXIncomingSASTransaction.h"
#import "MXOutgoingSASTransaction.h"

#import "MXEvent.h"
#import "MXHTTPOperation.h"

NS_ASSUME_NONNULL_BEGIN


#pragma mark - Constants

FOUNDATION_EXPORT NSString *const MXDeviceVerificationErrorDomain;

typedef enum : NSUInteger
{
    MXDeviceVerificationUnknownDeviceCode,
    MXDeviceVerificationUnsupportedMethodCode,
    MXDeviceVerificationUnknownRoomCode,
    MXDeviceVerificationUnknownIdentifier,
} MXDeviceVerificationErrorCode;


#pragma mark - Requests

/**
 Posted on new device verification request.
 */
FOUNDATION_EXPORT NSString *const MXDeviceVerificationManagerNewRequestNotification;

/**
 The key in the notification userInfo dictionary containing the `MXKeyVerificationRequest` instance.
 */
FOUNDATION_EXPORT NSString *const MXDeviceVerificationManagerNotificationRequestKey;



#pragma mark - Transactions

/**
 Posted on new device verification transaction.
 */
FOUNDATION_EXPORT NSString *const MXDeviceVerificationManagerNewTransactionNotification;

/**
 The key in the notification userInfo dictionary containing the `MXDeviceVerificationTransaction` instance.
 */
FOUNDATION_EXPORT NSString *const MXDeviceVerificationManagerNotificationTransactionKey;


/**
 The `MXDeviceVerificationManager` class instance manages interactive device
 verifications according to MSC1267 (Interactive key verification):
 https://github.com/matrix-org/matrix-doc/issues/1267.
 */
@interface MXDeviceVerificationManager : NSObject


#pragma mark - Requests

/**
 The timeout for requests.
 Default is 5 min.
 */
@property (nonatomic) NSTimeInterval requestTimeout;

/**
 Make a key verification request by Direct Message.

 @param userId the other user id.
 @param roomId the room to exchange direct messages. Nil to let SDK set up the room.
 @param fallbackText a text description if the app does not support verification by DM.
 @param methods Verification methods like MXKeyVerificationMethodSAS.
 @param success a block called when the operation succeeds.
 @param failure a block called when the operation fails.
 */
- (void)requestVerificationByDMWithUserId:(NSString*)userId
                                   roomId:(nullable NSString*)roomId
                             fallbackText:(NSString*)fallbackText
                                  methods:(NSArray<NSString*>*)methods
                                  success:(void(^)(MXKeyVerificationRequest *request))success
                                  failure:(void(^)(NSError *error))failure;

/**
 All pending verification requests.
 */
@property (nonatomic, readonly) NSArray<MXKeyVerificationRequest*> *pendingRequests;


#pragma mark - Transactions

/**
 Begin a device verification.

 @param userId the other user id.
 @param deviceId the other user device id.
 @param method the verification method (ex: MXKeyVerificationMethodSAS).
 @param success a block called when the operation succeeds.
 @param failure a block called when the operation fails.
 */
- (void)beginKeyVerificationWithUserId:(NSString*)userId
                           andDeviceId:(NSString*)deviceId
                                method:(NSString*)method
                               success:(void(^)(MXDeviceVerificationTransaction *transaction))success
                               failure:(void(^)(NSError *error))failure;

/**
 All transactions in progress.

 @param complete a block called with all transactions.
 */
- (void)transactions:(void(^)(NSArray<MXDeviceVerificationTransaction*> *transactions))complete;


#pragma mark - Verification status

/**
 Retrieve the verification status from an event.

 @param event an event in the verification process.
 @param success a block called when the operation succeeds.
 @param failure a block called when the operation fails.
 @return an HTTP operation or nil if the response is synchronous.
 */
- (nullable MXHTTPOperation *)keyVerificationFromKeyVerificationEvent:(MXEvent*)event
                                                              success:(void(^)(MXKeyVerification *keyVerification))success
                                                              failure:(void(^)(NSError *error))failure;

/**
 Extract the verification identifier from an event.

 @param event an event in the verification process.
 @return the key verification id. Nil if the event is not a verification event.
 */
- (nullable NSString *)keyVerificationIdFromDMEvent:(MXEvent*)event;

@end

NS_ASSUME_NONNULL_END

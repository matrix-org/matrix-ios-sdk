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
#import "MXKeyVerificationTransaction.h"
#import "MXKeyVerification.h"

#import "MXSASTransaction.h"

#import "MXQRCodeTransaction.h"

#import "MXEvent.h"
#import "MXHTTPOperation.h"

NS_ASSUME_NONNULL_BEGIN


#pragma mark - Constants

FOUNDATION_EXPORT NSString *const MXKeyVerificationErrorDomain;

typedef enum : NSUInteger
{
    MXKeyVerificationUnknownDeviceCode,
    MXKeyVerificatioNoOtherDeviceCode,
    MXKeyVerificationUnsupportedMethodCode,
    MXKeyVerificationInvalidStateCode,
    MXKeyVerificationUnknownRoomCode,
    MXKeyVerificationUnknownIdentifier,
} MXKeyVerificationErrorCode;


#pragma mark - Requests

/**
 Posted on new device verification request.
 */
FOUNDATION_EXPORT NSString *const MXKeyVerificationManagerNewRequestNotification;

/**
 The key in the notification userInfo dictionary containing the `MXKeyVerificationRequest` instance.
 */
FOUNDATION_EXPORT NSString *const MXKeyVerificationManagerNotificationRequestKey;



#pragma mark - Transactions

/**
 Posted on new device verification transaction.
 */
FOUNDATION_EXPORT NSString *const MXKeyVerificationManagerNewTransactionNotification;

/**
 The key in the notification userInfo dictionary containing the `MXKeyVerificationTransaction` instance.
 */
FOUNDATION_EXPORT NSString *const MXKeyVerificationManagerNotificationTransactionKey;


/**
 The `MXKeyVerificationManager` protocol specifies interactive key
 verifications according to MSC1267 (Interactive key verification):
 https://github.com/matrix-org/matrix-doc/issues/1267.
 */
@protocol MXKeyVerificationManager <NSObject>

#pragma mark - Requests

/**
 Make a key verification request by to_device events.
 
 @param userId the other user id.
 @param deviceIds array of device IDs to send requests to. Use nil for all other devices owned by the user
 @param methods Verification methods like MXKeyVerificationMethodSAS.
 @param success a block called when the operation succeeds.
 @param failure a block called when the operation fails.
 */
- (void)requestVerificationByToDeviceWithUserId:(NSString*)userId
                                      deviceIds:(nullable NSArray<NSString*>*)deviceIds
                                        methods:(NSArray<NSString*>*)methods
                                        success:(void(^)(id<MXKeyVerificationRequest> request))success
                                        failure:(void(^)(NSError *error))failure;

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
                                  success:(void(^)(id<MXKeyVerificationRequest> request))success
                                  failure:(void(^)(NSError *error))failure;

/**
 All pending verification requests.
 */
@property (nonatomic, readonly) NSArray<id<MXKeyVerificationRequest>> *pendingRequests;


#pragma mark - Transactions

/**
 Begin a device verification from a request.
 
 @param request the verification request.
 @param success a block called when the operation succeeds.
 @param failure a block called when the operation fails.
 */
- (void)beginKeyVerificationFromRequest:(id<MXKeyVerificationRequest>)request
                                 method:(NSString*)method
                                success:(void(^)(id<MXKeyVerificationTransaction> transaction))success
                                failure:(void(^)(NSError *error))failure;

/**
 All transactions in progress.

 @param complete a block called with all transactions.
 */
- (void)transactions:(void(^)(NSArray<id<MXKeyVerificationTransaction>> *transactions))complete;


#pragma mark - Verification status

/**
 Retrieve the verification status from an event.

 @param event an event in the verification process.
 @param success a block called when the operation succeeds.
 @param failure a block called when the operation fails.
 @return an HTTP operation or nil if the response is synchronous.
 */
- (nullable MXHTTPOperation *)keyVerificationFromKeyVerificationEvent:(MXEvent*)event
                                                               roomId:(NSString *)roomId
                                                              success:(void(^)(MXKeyVerification *keyVerification))success
                                                              failure:(void(^)(NSError *error))failure;

/**
 Retrieve pending QR code transaction

 @param transactionId The transaction id of the associated verification request event.
 @return MXQRCodeTransaction instance if a transaction exist or nil.
 */
- (nullable id<MXQRCodeTransaction>)qrCodeTransactionWithTransactionId:(NSString*)transactionId;

/**
 Remove pending QR code transaction.
 
 @param transactionId The transaction id of the associated verification request event.
 */
- (void)removeQRCodeTransactionWithTransactionId:(NSString*)transactionId;

@end

NS_ASSUME_NONNULL_END

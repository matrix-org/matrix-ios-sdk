/*
 Copyright 2019 New Vector Ltd

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

#import "MXDeviceVerificationTransaction.h"

#import "MXSASTransaction.h"
#import "MXIncomingSASTransaction.h"
#import "MXOutgoingSASTransaction.h"

NS_ASSUME_NONNULL_BEGIN


#pragma mark - Constants

/**
 Posted on new device verification transaction.
 */
FOUNDATION_EXPORT NSString *const kMXDeviceVerificationManagerNewTransactionNotification;

/**
 The key in the notification userInfo dictionary containing the `MXDeviceVerificationTransaction` instance.
 */
FOUNDATION_EXPORT NSString *const kMXDeviceVerificationManagerNotificationTransactionKey;


/**
 The `MXDeviceVerificationManager` class instance manages interactive device
 verifications according to MSC1267 (Interactive key verification):
 https://github.com/matrix-org/matrix-doc/issues/1267.
 */
@interface MXDeviceVerificationManager : NSObject

/**
 Begin a device verification.

 @param userId the other user id.
 @param deviceId the other user device id.
 @param method the verification method (ex: kMXKeyVerificationMethodSAS).
 @param complete block containing the created outgoing transaction. It is nil if the method is not supported.
 */
- (void)beginKeyVerificationWithUserId:(NSString*)userId
                           andDeviceId:(NSString*)deviceId
                                method:(NSString*)method
                              complete:(void (^)(MXDeviceVerificationTransaction * _Nullable transaction))complete;

@end

NS_ASSUME_NONNULL_END

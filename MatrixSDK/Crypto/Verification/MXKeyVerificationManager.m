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

#import "MXSession.h"
#import "MXTools.h"

#import "MXTransactionCancelCode.h"


#import "MXKeyVerificationRequestByToDeviceJSONModel.h"
#import "MXKeyVerificationRequestByDMJSONModel.h"

#import "MXQRCodeDataBuilder.h"

#import "MatrixSDKSwiftHeader.h"

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

static NSArray<MXEventTypeString> *kMXKeyVerificationManagerVerificationEventTypes;

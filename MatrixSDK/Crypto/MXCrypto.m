/*
 Copyright 2016 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd
 Copyright 2018 New Vector Ltd
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

#import "MXCrypto.h"

#import "MXCrypto_Private.h"

#import "MXSession.h"
#import "MXTools.h"

#import "MXOlmDevice.h"
#import "MXUsersDevicesMap.h"
#import "MXDeviceInfo.h"
#import "MXKey.h"

#import "MXRealmCryptoStore.h"
#import "MXCryptoMigration.h"

#import "MXMegolmSessionData.h"
#import "MXMegolmExportEncryption.h"

#import "MXOutgoingRoomKeyRequestManager.h"
#import "MXIncomingRoomKeyRequestManager.h"

#import "MXSecretStorage_Private.h"
#import "MXSecretShareManager_Private.h"
#import "MXRecoveryService_Private.h"

#import "MXKeyVerificationManager_Private.h"
#import "MXDeviceInfo_Private.h"
#import "MXCrossSigningInfo_Private.h"
#import "MXCrossSigning_Private.h"

#import "NSArray+MatrixSDK.h"

#import "MXDeviceListResponse.h"

#import "MatrixSDKSwiftHeader.h"
#import "MXSharedHistoryKeyService.h"
#import "MXNativeKeyBackupEngine.h"

#warning File has not been annotated with nullability, see MX_ASSUME_MISSING_NULLABILITY_BEGIN

/**
 The store to use for crypto.
 */
#define MXCryptoStoreClass MXRealmCryptoStore

NSString *const kMXCryptoRoomKeyRequestNotification = @"kMXCryptoRoomKeyRequestNotification";
NSString *const kMXCryptoRoomKeyRequestNotificationRequestKey = @"kMXCryptoRoomKeyRequestNotificationRequestKey";
NSString *const kMXCryptoRoomKeyRequestCancellationNotification = @"kMXCryptoRoomKeyRequestCancellationNotification";
NSString *const kMXCryptoRoomKeyRequestCancellationNotificationRequestKey = @"kMXCryptoRoomKeyRequestCancellationNotificationRequestKey";

NSString *const MXDeviceListDidUpdateUsersDevicesNotification = @"MXDeviceListDidUpdateUsersDevicesNotification";

static NSString *const kMXCryptoOneTimeKeyClaimCompleteNotification             = @"kMXCryptoOneTimeKeyClaimCompleteNotification";
static NSString *const kMXCryptoOneTimeKeyClaimCompleteNotificationDevicesKey   = @"kMXCryptoOneTimeKeyClaimCompleteNotificationDevicesKey";
static NSString *const kMXCryptoOneTimeKeyClaimCompleteNotificationErrorKey     = @"kMXCryptoOneTimeKeyClaimCompleteNotificationErrorKey";

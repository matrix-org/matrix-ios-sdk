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

#import "MXQRCodeTransaction.h"
#import "MXKeyVerificationTransaction_Private.h"
#import "MXQRCodeKeyVerificationStart.h"
#import "MXQRCodeData.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Constants

/**
 The `MXQRCodeTransaction` extension exposes internal operations.
 */
@interface MXLegacyQRCodeTransaction ()

@property (nonatomic) MXQRCodeTransactionState state;
@property (nonatomic, nullable) MXQRCodeKeyVerificationStart *startContent;
@property (nonatomic, strong, nullable) MXQRCodeData *qrCodeData; // Current user QR code, used to show, if support method MXKeyVerificationMethodQRCodeShow

- (nullable instancetype)initWithOtherDevice:(MXDeviceInfo*)otherDevice
                                  qrCodeData:(nullable MXQRCodeData*)qrCodeData
                                  andManager:(MXLegacyKeyVerificationManager *)manager;

- (void)handleStart:(MXQRCodeKeyVerificationStart*)startContent;

- (void)handleDone:(MXKeyVerificationDone*)doneEvent;

@end

NS_ASSUME_NONNULL_END

/*
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

#import "MXKeyVerificationRequest.h"

#import "MXKeyVerificationReady.h"
#import "MXKeyVerificationCancel.h"

MX_ASSUME_MISSING_NULLABILITY_BEGIN

@class MXLegacyKeyVerificationManager, MXHTTPOperation;


/**
 The `MXKeyVerificationRequest` extension exposes internal operations.
 */
@interface MXLegacyKeyVerificationRequest ()

@property (nonatomic, readonly, weak) MXLegacyKeyVerificationManager *manager;

- (instancetype)initWithEvent:(MXEvent*)event andManager:(MXLegacyKeyVerificationManager*)manager;

@property (nonatomic, nullable) MXTransactionCancelCode *reasonCancelCode;
@property (nonatomic) BOOL isFromMyUser;
@property (nonatomic) BOOL isFromMyDevice;

@property (nonatomic) MXKeyVerificationReady *acceptedData;

- (void)updateState:(MXKeyVerificationRequestState)state notifiy:(BOOL)notify;

- (void)handleReady:(MXKeyVerificationReady*)readyContent;
- (void)handleCancel:(MXKeyVerificationCancel*)cancelContent;

@end

MX_ASSUME_MISSING_NULLABILITY_END

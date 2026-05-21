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


#import "MXCryptoTools.h"
#import "NSArray+MatrixSDK.h"

#import "MXQRCodeDataCoder.h"
#import "MXBase64Tools.h"

#import "MXVerifyingAnotherUserQRCodeData.h"
#import "MXSelfVerifyingMasterKeyTrustedQRCodeData.h"
#import "MXSelfVerifyingMasterKeyNotTrustedQRCodeData.h"

NSString * const MXKeyVerificationMethodQRCodeShow  = @"m.qr_code.show.v1";
NSString * const MXKeyVerificationMethodQRCodeScan  = @"m.qr_code.scan.v1";

NSString * const MXKeyVerificationMethodReciprocate = @"m.reciprocate.v1";

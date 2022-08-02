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

#import <XCTest/XCTest.h>

#import "MXQRCodeDataCoder.h"
#import "MXQRCodeDataBuilder.h"
#import "MXVerifyingAnotherUserQRCodeData.h"

@interface MXQRCodeDataUnitTests : XCTestCase

@end

@implementation MXQRCodeDataUnitTests

- (void)testDecode
{
    MXQRCodeVerificationMode expectedVerificationMode = MXQRCodeVerificationModeVerifyingAnotherUser;
    NSString *expectedTransactionId = @"$zoeruzeprupzouerpzeupir";
    NSString *expectedFirstKey = @"ktEwcUP6su1xh+GuE+CYkQ3H6W/DIl+ybHFdaEOrolU";
    NSString *expectedSecondKey = @"TXluZKTZLvSRWOTPlOqLq534bA+/K4zLFKSu9cGLQaU";
    NSData *expectedSharedSecret = [@"MTIzNDU2Nzg" dataUsingEncoding:NSASCIIStringEncoding];
    
    MXQRCodeDataBuilder *qrCodeDataBuilder = [MXQRCodeDataBuilder new];
    MXQRCodeDataCoder *qrCodeDataCoder = [MXQRCodeDataCoder new];
    
    MXQRCodeData *qrCodeData = [qrCodeDataBuilder buildQRCodeDataWithVerificationMode:expectedVerificationMode
                                                                        transactionId:expectedTransactionId
                                                                             firstKey:expectedFirstKey
                                                                            secondKey:expectedSecondKey
                                                                         sharedSecret:expectedSharedSecret];
    
    NSData *qrCodeRawData = [qrCodeDataCoder encode:qrCodeData];
    
    XCTAssertNotNil(qrCodeRawData);
        
    MXQRCodeData *decodedQRCodeData = [qrCodeDataCoder decode:qrCodeRawData];
    
    XCTAssertNotNil(decodedQRCodeData);
    XCTAssertTrue([decodedQRCodeData isKindOfClass:MXVerifyingAnotherUserQRCodeData.class]);
    XCTAssertEqual(decodedQRCodeData.verificationMode, expectedVerificationMode);
    XCTAssertEqualObjects(decodedQRCodeData.transactionId, expectedTransactionId);
    XCTAssertEqualObjects(decodedQRCodeData.firstKey, expectedFirstKey);
    XCTAssertEqualObjects(decodedQRCodeData.secondKey, expectedSecondKey);
    XCTAssertEqualObjects(decodedQRCodeData.sharedSecret, expectedSharedSecret);
}

@end

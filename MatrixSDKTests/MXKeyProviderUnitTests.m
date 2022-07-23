// 
// Copyright 2020 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <XCTest/XCTest.h>
#import "MXKeyProvider.h"
#import "MXAesKeyData.h"
#import "MXRawDataKey.h"

@interface MXKeyProviderUnitTests : XCTestCase <MXKeyProviderDelegate>

@property (nonatomic) BOOL isEncryptionAvailable;
@property (nonatomic, strong, nullable) MXKeyData *currentKey;

@end

@implementation MXKeyProviderUnitTests

- (void)setUp {
    [super setUp];
    self.isEncryptionAvailable = YES;
    NSData *iv = [@"baB6pgMP9erqSaKF" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *aesKey = [@"6fXK17pQFUrFqOnxt3wrqz8RHkQUT9vQ" dataUsingEncoding:NSUTF8StringEncoding];
    self.currentKey = [MXAesKeyData dataWithIv:iv key:aesKey];
    [MXKeyProvider sharedInstance].delegate = self;
}

- (void)tearDown {
    [super tearDown];
}

- (void)testNoDelegateSet {
    [MXKeyProvider sharedInstance].delegate = nil;
    
    @try {
        MXKeyData *key = [[MXKeyProvider sharedInstance] requestKeyForDataOfType:@"MXKeyProviderTests" isMandatory:YES expectedKeyType:kAes];
        XCTAssertNil(key);
        
        key = [[MXKeyProvider sharedInstance] requestKeyForDataOfType:@"MXKeyProviderTests" isMandatory:NO expectedKeyType:kAes];
        XCTAssertNil(key);
        
        key = [[MXKeyProvider sharedInstance] requestKeyForDataOfType:@"MXKeyProviderTests" isMandatory:YES expectedKeyType:kRawData];
        XCTAssertNil(key);
    } @catch (NSException *exception) {
        XCTFail(@"Unexpected exception raised: %@", exception);
    }
}

- (void)testEncryptionNotAvailable {
    self.isEncryptionAvailable = NO;
    
    @try {
        MXKeyData *key = [[MXKeyProvider sharedInstance] requestKeyForDataOfType:@"MXKeyProviderTests" isMandatory:YES expectedKeyType:kAes];
        XCTAssertNil(key);
        
        key = [[MXKeyProvider sharedInstance] requestKeyForDataOfType:@"MXKeyProviderTests" isMandatory:NO expectedKeyType:kAes];
        XCTAssertNil(key);
        
        key = [[MXKeyProvider sharedInstance] requestKeyForDataOfType:@"MXKeyProviderTests" isMandatory:YES expectedKeyType:kRawData];
        XCTAssertNil(key);
    } @catch (NSException *exception) {
        XCTFail(@"Unexpected exception raised: %@", exception);
    }
}

- (void)testAllSet {
    @try {
        MXKeyData *key = [[MXKeyProvider sharedInstance] requestKeyForDataOfType:@"MXKeyProviderTests" isMandatory:YES expectedKeyType:kAes];
        XCTAssert(key == self.currentKey);
    } @catch (NSException *exception) {
        XCTFail(@"Unexpected exception raised: %@", exception);
    }
}

- (void)testKeyNotAvailable {
    self.currentKey = nil;
    
    @try {
        MXKeyData *key = [[MXKeyProvider sharedInstance] requestKeyForDataOfType:@"MXKeyProviderTests" isMandatory:NO expectedKeyType:kAes];
        XCTAssertNil(key);
    } @catch (NSException *exception) {
        XCTFail(@"Unexpected exception raised (key not mandatory): %@", exception);
    }
    
    @try {
        [[MXKeyProvider sharedInstance] requestKeyForDataOfType:@"MXKeyProviderTests" isMandatory:YES expectedKeyType:kAes];
        XCTFail(@"Exception should be raised as the key is mandatory but not set yet.");
    } @catch (NSException *exception) {
    }
}

- (void)testInvalidKeyType {
    @try {
        [[MXKeyProvider sharedInstance] requestKeyForDataOfType:@"MXKeyProviderTests" isMandatory:NO expectedKeyType:kRawData];
        XCTFail(@"Exception should be raised as the key type does not match.");
    } @catch (NSException *exception) {
    }
}

#pragma mark - MXKeyProviderDelegate

- (BOOL)isEncryptionAvailableForDataOfType:(nonnull NSString *)dataType {
    return self.isEncryptionAvailable;
}

- (BOOL)hasKeyForDataOfType:(nonnull NSString *)dataType {
    return self.currentKey != nil;
}

- (nullable MXKeyData *)keyDataForDataOfType:(nonnull NSString *)dataType {
    return self.currentKey;
}

@end

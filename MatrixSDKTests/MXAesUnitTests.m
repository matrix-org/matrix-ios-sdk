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
#import "MXAes.h"

@interface MXAesUnitTests : XCTestCase

@property(nonatomic, strong) NSData *data;
@property(nonatomic, strong) NSData *data2;
@property(nonatomic, strong) NSData *iv;
@property(nonatomic, strong) NSData *iv2;
@property(nonatomic, strong) NSData *aesKey;
@property(nonatomic, strong) NSData *aesKey2;

@end

@implementation MXAesUnitTests

- (void)setUp
{
    // Put setup code here. This method is called before the invocation of each test method in the class.
    self.data = [@"My test data" dataUsingEncoding:NSUTF8StringEncoding];
    self.data2 = [@"My test data2" dataUsingEncoding:NSUTF8StringEncoding];
    self.iv = [@"baB6pgMP9erqSaKF" dataUsingEncoding:NSUTF8StringEncoding];
    self.iv2 = [@"q9M05wN0JNUl4h6v" dataUsingEncoding:NSUTF8StringEncoding];
    self.aesKey = [@"6fXK17pQFUrFqOnxt3wrqz8RHkQUT9vQ" dataUsingEncoding:NSUTF8StringEncoding];
    self.aesKey2 = [@"abPsPqzn1GUTTG3Bk7cTce4CUWS57GuK" dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testIvGeneration {
    XCTAssertNotNil([MXAes iv]);
}

- (void)testIvUniqueness {
    XCTAssert(![[MXAes iv] isEqualToData:[MXAes iv]]);
}

- (void)testEncryption {
    NSError *error = nil;
    NSData *cipher = [MXAes encrypt:self.data aesKey:self.aesKey iv:self.iv error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(cipher);
    XCTAssert(![self.data isEqual:cipher]);
}

- (void)testEncryptionConsistency {
    NSError *error = nil;
    NSData *cipher1 = [MXAes encrypt:self.data aesKey:self.aesKey iv:self.iv error:&error];
    XCTAssertNil(error);
    NSData *cipher2 = [MXAes encrypt:self.data aesKey:self.aesKey iv:self.iv error:&error];
    XCTAssertNil(error);
    XCTAssert([cipher1 isEqual:cipher2]);
}

- (void)testEncryptionUniqueness {
    NSError *error = nil;
    NSData *cipher1 = [MXAes encrypt:self.data aesKey:self.aesKey iv:self.iv error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(cipher1);

    NSData *cipher2 = [MXAes encrypt:self.data aesKey:self.aesKey2 iv:self.iv error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(cipher2);
    XCTAssert(![cipher1 isEqual:cipher2]);

    NSData *cipher3 = [MXAes encrypt:self.data aesKey:self.aesKey iv:self.iv2 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(cipher3);
    XCTAssert(![cipher1 isEqual:cipher3]);

    NSData *cipher4 = [MXAes encrypt:self.data2 aesKey:self.aesKey iv:self.iv error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(cipher4);
    XCTAssert(![cipher1 isEqual:cipher4]);
}

- (void)testEcryptionReversibility {
    NSError *error = nil;
    NSData *cipher = [MXAes encrypt:self.data aesKey:self.aesKey iv:self.iv error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(cipher);
    
    NSData *decrypt = [MXAes decrypt:cipher aesKey:self.aesKey iv:self.iv error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(decrypt);
    XCTAssert([self.data isEqual:decrypt]);
}

- (void)testEcryptionSecurity {
    NSError *error = nil;
    NSData *cipher = [MXAes encrypt:self.data aesKey:self.aesKey iv:self.iv error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(cipher);
    
    NSData *decrypt1 = [MXAes decrypt:cipher aesKey:self.aesKey2 iv:self.iv error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(decrypt1);
    XCTAssert(![self.data isEqual:decrypt1]);
    
    NSData *decrypt2 = [MXAes decrypt:cipher aesKey:self.aesKey iv:self.iv2 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(decrypt2);
    XCTAssert(![self.data isEqual:decrypt2]);
    
    NSData *decrypt3 = [MXAes decrypt:cipher aesKey:self.aesKey2 iv:self.iv2 error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(decrypt3);
    XCTAssert(![self.data isEqual:decrypt3]);
}

@end

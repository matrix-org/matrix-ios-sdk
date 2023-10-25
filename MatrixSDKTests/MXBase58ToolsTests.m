// 
// Copyright 2023 The Matrix.org Foundation C.I.C
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

#import "MXBase58Tools.h"

@interface MXBase58ToolsTests : XCTestCase

@property NSArray<NSDictionary *> *kDecodedStringsToBase58EncodedStrings;
@property NSArray<NSString *> *kInvalidBase58EncodedStrings;
@property NSArray<NSDictionary *> *kDecodedDataAsHexStringsToBase58EncodedStrings;

@end

@implementation MXBase58ToolsTests

#pragma mark - SetUp (Constants definitions)

- (void)setUp
{
    [super setUp];

    _kDecodedStringsToBase58EncodedStrings = @[
        @{@"": @""},
        @{@" ": @"Z"},
        @{@"-": @"n"},
        @{@"0": @"q"}, // this decoded symbol is not part of the Base58 alphabet
        @{@"1": @"r"},
        @{@"2": @"s"},
        @{@"3": @"t"},
        @{@"4": @"u"},
        @{@"5": @"v"},
        @{@"6": @"w"},
        @{@"7": @"x"},
        @{@"8": @"y"},
        @{@"9": @"z"},
        @{@"A": @"28"},
        @{@"B": @"29"},
        @{@"C": @"2A"},
        @{@"D": @"2B"},
        @{@"E": @"2C"},
        @{@"F": @"2D"},
        @{@"G": @"2E"},
        @{@"H": @"2F"},
        @{@"I": @"2G"}, // this decoded symbol is not part of the Base58 alphabet
        @{@"J": @"2H"},
        @{@"K": @"2J"},
        @{@"L": @"2K"},
        @{@"M": @"2L"},
        @{@"N": @"2M"},
        @{@"O": @"2N"}, // this decoded symbol is not part of the Base58 alphabet
        @{@"P": @"2P"},
        @{@"Q": @"2Q"},
        @{@"R": @"2R"},
        @{@"S": @"2S"},
        @{@"T": @"2T"},
        @{@"U": @"2U"},
        @{@"V": @"2V"},
        @{@"W": @"2W"},
        @{@"X": @"2X"},
        @{@"Y": @"2Y"},
        @{@"Z": @"2Z"},
        @{@"a": @"2g"},
        @{@"b": @"2h"},
        @{@"c": @"2i"},
        @{@"d": @"2j"},
        @{@"e": @"2k"},
        @{@"f": @"2m"},
        @{@"g": @"2n"},
        @{@"h": @"2o"},
        @{@"i": @"2p"},
        @{@"j": @"2q"},
        @{@"k": @"2r"},
        @{@"l": @"2s"}, // this decoded symbol is not part of the Base58 alphabet
        @{@"m": @"2t"},
        @{@"n": @"2u"},
        @{@"o": @"2v"},
        @{@"p": @"2w"},
        @{@"q": @"2x"},
        @{@"r": @"2y"},
        @{@"s": @"2z"},
        @{@"t": @"31"},
        @{@"u": @"32"},
        @{@"v": @"33"},
        @{@"w": @"34"},
        @{@"x": @"35"},
        @{@"y": @"36"},
        @{@"z": @"37"},
        @{@"-1": @"4SU"},
        @{@"11": @"4k8"},
        @{@"abc": @"ZiCa"},
        @{@"1234598760": @"3mJr7AoUXx2Wqd"},
        @{@"abcdefghijklmnopqrstuvwxyz": @"3yxU3u1igY8WkgtjK92fbJQCd4BZiiT1v25f"},
        @{@"00000000000000000000000000000000000000000000000000000000000000": @"3sN2THZeE9Eh9eYrwkvZqNstbHGvrxSAM7gXUXvyFQP8XvQLUqNCS27icwUeDT7ckHm4FUHM2mTVh1vbLmk7y"},
        @{@"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz": @"SxQSv8AWonnsWRyFyqRoAk1kUMEC2Xz7Q9UVuUhunVEat1Axfb3YAZRqeR1QtxBTdsnvtWzzKmidgUq"},
        @{@"Test string": @"MvqLnZUGUgNbDx2"},
        @{@"Lorem ipsum": @"KxLQv2iZ3oVEumW"}
    ];

    _kInvalidBase58EncodedStrings = @[
        @"0",
        @"O",
        @"I",
        @"l",
        @"3mJr0",
        @"O3yxU",
        @"3sNI",
        @"4kl8",
        @"0OIl",
        @"!@#$%^&*()-_=+~`"
    ];

    _kDecodedDataAsHexStringsToBase58EncodedStrings = @[
        @{@"00662ad25db00e7bb38bc04831ae48b4b446d1269817d515b6": @"1AKDDsfTh8uY4X3ppy1m7jw1fVMBSMkzjP"},
        @{@"61": @"2g"},
        @{@"626262": @"a3gV"},
        @{@"636363": @"aPEr"},
        @{@"73696d706c792061206c6f6e6720737472696e67": @"2cFupjhnEsSn59qHXstmK2ffpLv2"},
        @{@"00eb15231dfceb60925886b67d065299925915aeb172c06647": @"1NS17iag9jJgTHD1VXjvLCEnZuQ3rJDE9L"},
        @{@"516b6fcd0f": @"ABnLTmg"},
        @{@"bf4f89001e670274dd": @"3SEo3LWLoPntC"},
        @{@"572e4794": @"3EFU7m"},
        @{@"ecac89cad93923c02321": @"EJDM8drfXA6uyA"},
        @{@"10c8511e": @"Rt5zm"},
        @{@"00000000000000000000": @"1111111111"},
        @{@"8b0177076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2aee": @"EsTcLW2KPGiFwKEA3As5g5c4BXwkqeeJZJV8Q9fugUMNUE4d"},
        @{@"8b01c8e396a0dbfed5e8d647fc19f0a1b334791ffd63069727da0f2cb9e796212f732f": @"EsU2ev6p4pNz1NgfpbDFYpq9K5ygQEd5X1s28Bg5iTGMSRQJ"},
        @{@"8b0177076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2aef": @"EsTcLW2KPGiFwKEA3As5g5c4BXwkqeeJZJV8Q9fugUMNUE4e"}
    ];
}

- (void)tearDown
{
    [super tearDown];
}

#pragma mark - Tests

- (void)testDataFromBase58WithEncodedStrings
{
    for (NSDictionary *dict in _kDecodedStringsToBase58EncodedStrings) {
        for (NSString *expectedDecodedString in dict) {
            NSString *sourceEncodedString = dict[expectedDecodedString];

            NSData *actualResultDecodedData = [MXBase58Tools dataFromBase58:sourceEncodedString];
            NSString *actualResultDecodedStrg = [[NSString alloc] initWithData:actualResultDecodedData encoding:NSUTF8StringEncoding];

            XCTAssertEqualObjects(actualResultDecodedStrg, expectedDecodedString);
        }
    }
}

- (void)testDataFromBase58WithInvalidEncodedStrings
{
    for (NSString* invalidBase58EncodedString in _kInvalidBase58EncodedStrings)
    {
        NSData *actualResultDecodedData = [MXBase58Tools dataFromBase58:invalidBase58EncodedString];
        XCTAssertNil(actualResultDecodedData, @"Decoding should return nil for invalid Base64 string: %@", invalidBase58EncodedString);
    }
}

- (void)testDataFromBase58WithHexStrings
{
    for (NSDictionary *dict in _kDecodedDataAsHexStringsToBase58EncodedStrings) {
        for (NSString *expectedDecodedDataAsHexString in dict) {
            NSString *sourceEncodedString = dict[expectedDecodedDataAsHexString];

            NSData *actualResultDecodedData = [MXBase58Tools dataFromBase58:sourceEncodedString];
            NSString *actualResultDecodedDataAsHexString = [self hexStringFromData:actualResultDecodedData];

            XCTAssertEqualObjects(actualResultDecodedDataAsHexString, expectedDecodedDataAsHexString);
        }
    }
}

- (void)testBase58FromDataWithDecodedStrings
{
    for (NSDictionary *dict in _kDecodedStringsToBase58EncodedStrings) {
        for (NSString *sourceDecodedString in dict) {
            NSString *expectedEncodedString = dict[sourceDecodedString];

            NSData *sourceDecodedData = [sourceDecodedString dataUsingEncoding:NSUTF8StringEncoding];
            NSString *actualResultEncodedStrg = [MXBase58Tools base58FromData:sourceDecodedData];

            XCTAssertEqualObjects(actualResultEncodedStrg, expectedEncodedString);
        }
    }
}

- (void)testBase58FromDataWithEmptyData
{
    NSData *emptyData = [[NSData alloc] init];
    NSString *expectedEncodedString = @"";

    NSString *actualResultEncodedStrg = [MXBase58Tools base58FromData:emptyData];

    XCTAssertEqualObjects(actualResultEncodedStrg, expectedEncodedString);
}

- (void)testEncodeBase58WithHexStrings
{
    for (NSDictionary *dict in _kDecodedDataAsHexStringsToBase58EncodedStrings) {
        for (NSString *sourceDecodedDataAsHexString in dict) {
            NSString *expectedEncodedString = dict[sourceDecodedDataAsHexString];

            NSData *sourceDecodedData = [self dataFromHexString:sourceDecodedDataAsHexString];
            NSString *actualResultEncodedStrg = [MXBase58Tools base58FromData:sourceDecodedData];

            XCTAssertEqualObjects(actualResultEncodedStrg, expectedEncodedString);
        }
    }
}

#pragma mark - Helpers

/**
 Convert the specified data to a hexadecimal string.

 @param data data to be converted.
 @return hexadecimal string of data. An empty string is returned if the specified data is empty.
 */
- (NSString *)hexStringFromData:(NSData *)data
{
    const unsigned char *dataBuffer = (const unsigned char *)[data bytes];

    if (!dataBuffer)
        return [NSString string];

    NSUInteger dataLength = [data length];
    NSMutableString *hexString = [NSMutableString stringWithCapacity:(dataLength * 2)];

    for (int i = 0; i < dataLength; ++i)
        [hexString appendString:[NSString stringWithFormat:@"%02lx", (unsigned long)dataBuffer[i]]];

    return [NSString stringWithString:hexString];
}

/**
 Convert the specified hexadecimal string to data.

 @param hexString hexadecimal string to be converted. May contain spaces between bytes.
 @return data of hexadecimal string.
 */
- (NSData *)dataFromHexString:(NSString *)hexString
{
    NSString *string = [hexString stringByReplacingOccurrencesOfString:@" " withString:@""];
    NSMutableData *data= [[NSMutableData alloc] init];
    unsigned char whole_byte;
    char byte_chars[3] = {'\0','\0','\0'};
    int i;
    for (i=0; i < [string length]/2; i++) {
        byte_chars[0] = [string characterAtIndex:i*2];
        byte_chars[1] = [string characterAtIndex:i*2+1];
        whole_byte = strtol(byte_chars, NULL, 16);
        [data appendBytes:&whole_byte length:1];
    }
    return data;
}

@end

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

#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"

#import "MXMemoryStore.h"
#import "MatrixSDKTestsSwiftHeader.h"

#import <OHHTTPStubs/HTTPStubs.h>

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXCryptoShareTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;
}
@end

@implementation MXCryptoShareTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:matrixSDKTestsData];
}

- (void)tearDown
{
    matrixSDKTestsData = nil;
    matrixSDKTestsE2EData = nil;
    
    [HTTPStubs removeAllStubs];

    [super tearDown];
}

#pragma mark - Helpers

/**
 Send message and await its delivery
 */
- (void)sendMessage:(NSString *)message room:(MXRoom *)room success:(void(^)(void))success failure:(void(^)(NSError *error))failure
{
    __block id listener = [room listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage]
                                              onEvent:^(MXEvent * _Nonnull event, MXTimelineDirection direction, MXRoomState * _Nullable roomState)
    {
        [room removeListener:listener];
        success();
    }];
    
    [room sendTextMessage:message threadId:nil success:nil failure:failure];
}

/**
 Set room visibility and awaits its processing
 */
- (void)setHistoryVisibility:(MXRoomHistoryVisibility)historyVisibility room:(MXRoom *)room success:(void(^)(void))success failure:(void(^)(NSError *error))failure
{
    __block id listener = [room listenToEventsOfTypes:@[kMXEventTypeStringRoomHistoryVisibility]
                                              onEvent:^(MXEvent * _Nonnull event, MXTimelineDirection direction, MXRoomState * _Nullable roomState)
    {
        [room removeListener:listener];
        success();
    }];
    
    [room setHistoryVisibility:historyVisibility success:nil failure:failure];
}

@end

#pragma clang diagnostic pop

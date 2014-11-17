/*
 Copyright 2014 OpenMarket Ltd
 
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

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"

#import "MXSession.h"

@interface MXRoomStateDynamicTests : XCTestCase
{
    MXSession *mxSession;
}
@end

@implementation MXRoomStateDynamicTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    if (mxSession)
    {
        [mxSession close];
        mxSession = nil;
    }
    [super tearDown];
}

/*
 Creates a room with the following historic:
 
 1 - Bob creates a private room
 2 - Bob: "Hello World"
 3 - Bob changes the room topic to "Room state dynamic test"
 4 - Bob: "test" 
 */
- (void)createScenario1:(XCTestCase*)testCase
            readyToTest:(void (^)(NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:testCase
                                                                     newTextMessage:@"Hello World"
                                                                      onReadyToTest:^(MXRestClient *bobRestClient, NSString *room_id, NSString *new_text_message_event_id, XCTestExpectation *expectation) {
                                                                          
                                                                      }];
}

/*
 Creates a room with the following historic:
 
 1 - Bob creates a private room
 2 - Bob: "Hello World"
 3 - Bob invites Alice
 4 - Bob: "I wait for Alice"
 5 - Alice joins
 6 - Alice: "Hi"
 7 - Alice changes her displayname to "Alice in Wonderland"
 8 - Alice: "What's going on?"
 */
- (void)createScenario2:(XCTestCase*)testCase
                                   readyToTest:(void (^)(NSString *roomId, XCTestExpectation *expectation))readyToTest
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:testCase
                                                                     newTextMessage:@"Hello World"
                                                                      onReadyToTest:^(MXRestClient *bobRestClient, NSString *room_id, NSString *new_text_message_event_id, XCTestExpectation *expectation) {
                                                                          
                                                                      }];
}

 


@end

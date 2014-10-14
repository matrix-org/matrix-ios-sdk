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

#import "MXData.h"

@interface MXDataTests : XCTestCase
{
    MXData *matrixData;
}
@end

@implementation MXDataTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    [matrixData close];
    matrixData = nil;
    
    [super tearDown];
}


- (void)testRecents
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXSession *bobSession, NSString *room_id, NSString *new_text_message_event_id, XCTestExpectation *expectation) {
        
        matrixData = [[MXData alloc] initWithMatrixSession:bobSession];
        [matrixData start:^{
            
            NSArray *recents = [matrixData recents];
            
            XCTAssertGreaterThan(recents.count, 0, @"There must be at least one recent");
            
            MXEvent *myNewTextMessageEvent;
            for (MXEvent *event in recents)
            {
                XCTAssertNotNil(event.event_id, @"The event must have an event_id to be valid");
                
                if ([event.event_id isEqualToString:new_text_message_event_id])
                {
                    myNewTextMessageEvent = event;
                }
            }
            
            XCTAssertNotNil(myNewTextMessageEvent);
            XCTAssertTrue([myNewTextMessageEvent.type isEqualToString:kMXEventTypeStringRoomMessage]);
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testRecentsOrder
{
    [[MatrixSDKTestsData sharedData]doMXSessionTestWihBobAndSeveralRoomsAndMessages:self readyToTest:^(MXSession *bobSession, XCTestExpectation *expectation) {

        matrixData = [[MXData alloc] initWithMatrixSession:bobSession];
        [matrixData start:^{
            
            NSArray *recents = [matrixData recents];
            
            XCTAssertGreaterThanOrEqual(recents.count, 5, @"There must be at least 5 recents");
            
            NSUInteger prev_ts = ULONG_MAX;
            for (MXEvent *event in recents)
            {
                XCTAssertNotNil(event.event_id, @"The event must have an event_id to be valid");
                
                if (event.ts)
                {
                    XCTAssertLessThanOrEqual(event.ts, prev_ts, @"Events must be listed in antichronological order");
                    prev_ts = event.ts;
                }
                else
                {
                    NSLog(@"No timestamp in the event data: %@", event);
                }
            }
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


@end

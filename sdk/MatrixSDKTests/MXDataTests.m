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
    if (matrixData)
    {
        [matrixData close];
        matrixData = nil;
    }
    [super tearDown];
}


- (void)testRecents
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobSession, NSString *room_id, NSString *new_text_message_event_id, XCTestExpectation *expectation) {
        
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
    [[MatrixSDKTestsData sharedData]doMXSessionTestWihBobAndSeveralRoomsAndMessages:self readyToTest:^(MXRestClient *bobSession, XCTestExpectation *expectation) {

        matrixData = [[MXData alloc] initWithMatrixSession:bobSession];
        [matrixData start:^{
            
            NSArray *recents = [matrixData recents];
            
            XCTAssertGreaterThanOrEqual(recents.count, 5, @"There must be at least 5 recents");
            
            NSUInteger prev_ts = ULONG_MAX;
            for (MXEvent *event in recents)
            {
                XCTAssertNotNil(event.event_id, @"The event must have an event_id to be valid");
                
                if (event.origin_server_ts)
                {
                    XCTAssertLessThanOrEqual(event.origin_server_ts, prev_ts, @"Events must be listed in antichronological order");
                    prev_ts = event.origin_server_ts;
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


- (void)testListenerForAllLiveEvents
{
    [[MatrixSDKTestsData sharedData]doMXSessionTestWihBobAndSeveralRoomsAndMessages:self readyToTest:^(MXRestClient *bobSession, XCTestExpectation *expectation) {
        
        matrixData = [[MXData alloc] initWithMatrixSession:bobSession];
        
        // The listener must catch at least these events
        __block NSMutableArray *expectedEvents =
        [NSMutableArray arrayWithArray:@[
                                         kMXEventTypeStringRoomCreate,
                                         kMXEventTypeStringRoomMember,
                                         
                                         // Expect the 5 text messages created by doMXSessionTestWithBobAndARoomWithMessages
                                         kMXEventTypeStringRoomMessage,
                                         kMXEventTypeStringRoomMessage,
                                         kMXEventTypeStringRoomMessage,
                                         kMXEventTypeStringRoomMessage,
                                         kMXEventTypeStringRoomMessage,
                                         ]];
        
        [matrixData registerEventListenerForTypes:nil block:^(MXData *matrixData, MXEvent *event, BOOL isLive) {
            
            if (isLive)
            {
                [expectedEvents removeObject:event.type];
                
                if (0 == expectedEvents.count)
                {
                    XCTAssert(YES, @"All expected events must be catch");
                    [expectation fulfill];
                }
            }
            
        }];
        
        
        // Create a room with messages in parallel
        [matrixData start:^{
            
            [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:nil readyToTest:^(MXRestClient *bobSession, NSString *room_id, XCTestExpectation *expectation) {
            }];
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)testListenerForRoomMessageOnly
{
    [[MatrixSDKTestsData sharedData]doMXSessionTestWihBobAndSeveralRoomsAndMessages:self readyToTest:^(MXRestClient *bobSession, XCTestExpectation *expectation) {
        
        matrixData = [[MXData alloc] initWithMatrixSession:bobSession];
        
        // Listen to m.room.message only
        // We should not see events coming before (m.room.create, and all state events)
        [matrixData registerEventListenerForTypes:@[kMXEventTypeStringRoomMessage]
                                            block:^(MXData *matrixData, MXEvent *event, BOOL isLive) {
            
            if (isLive)
            {
                XCTAssertEqual(event.eventType, MXEventTypeRoomMessage, @"We must receive only m.room.message event - Event: %@", event);
                [expectation fulfill];
            }
            
        }];
        
        
        // Create a room with messages in parallel
        [matrixData start:^{
            
            [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:nil readyToTest:^(MXRestClient *bobSession, NSString *room_id, XCTestExpectation *expectation) {
            }];
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

@end

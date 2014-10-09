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

// Prepare a MXSession for mxBob so that we can make test on it
- (void)doMXDataTestInABobRoomAndANewTextMessage:(NSString*)newTextMessage
                                   onReadyToTest:(void (^)(MXSession *bobSession, NSString* room_id, NSString* new_text_message_event_id, XCTestExpectation *expectation))readyToTest
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData getBobMXSession:^(MXSession *bobSession) {
        // Create a random room to use
        [bobSession createRoom:nil visibility:nil room_alias_name:nil topic:nil invite:nil success:^(MXCreateRoomResponse *response) {
            
            // Post the the message text in it
            [bobSession postTextMessage:response.room_id text:newTextMessage success:^(NSString *event_id) {
                
                readyToTest(bobSession, response.room_id, event_id, expectation);
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions");
            }];
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot create a room - error: %@", error);
        }];
    }];

    [self waitForExpectationsWithTimeout:10000 handler:nil];
}

- (void)doMXDataTestWihBobAndSeveralRoomsAndMessages:(void (^)(MXSession *bobSession, XCTestExpectation *expectation))readyToTest
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];
    
    MatrixSDKTestsData *sharedData = [MatrixSDKTestsData sharedData];
    
    [sharedData getBobMXSession:^(MXSession *bobSession) {
        
        // Fill Bob's account with 5 rooms of 3 messages
        [sharedData for:bobSession createRooms:5 withMessages:3 success:^{
            readyToTest(bobSession, expectation);
        }];
    }];
    
    [self waitForExpectationsWithTimeout:10000 handler:nil];
}

- (void)testRecents
{
    [self doMXDataTestInABobRoomAndANewTextMessage:@"This is a text message for recents" onReadyToTest:^(MXSession *bobSession, NSString *room_id, NSString *new_text_message_event_id, XCTestExpectation *expectation) {
        
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
            XCTAssertTrue([myNewTextMessageEvent.type isEqualToString:kMXEventTypeRoomMessage]);
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testRecentsOrder
{
    [self doMXDataTestWihBobAndSeveralRoomsAndMessages:^(MXSession *bobSession, XCTestExpectation *expectation) {

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

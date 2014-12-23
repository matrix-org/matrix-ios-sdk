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

@interface MXRoomTests : XCTestCase
{
    MXSession *mxSession;
}

@end

@implementation MXRoomTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    if (mxSession)
    {
        [[MatrixSDKTestsData sharedData] closeMXSession:mxSession];
        mxSession = nil;
    }
    [super tearDown];
}


- (void)testListenerForAllLiveEvents
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        __block NSString *sentMessageEventID;
        __block NSString *receivedMessageEventID;
        
        void (^checkEventIDs)() = ^ void ()
        {
            if (sentMessageEventID && receivedMessageEventID)
            {
                XCTAssertTrue([receivedMessageEventID isEqualToString:sentMessageEventID]);
                
                [expectation fulfill];
            }
        };
        
        // Register the listener
        [room listenToEvents:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
            
            XCTAssertEqual(direction, MXEventDirectionForwards);
            
            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
            
            XCTAssertNotNil(event.eventId);
            
            receivedMessageEventID = event.eventId;
           
            checkEventIDs();
        }];
        
        
        // Populate a text message in parallel
        [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndThePublicRoom:nil readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {
            
            [bobRestClient sendTextMessageToRoom:roomId text:@"Hello listeners!" success:^(NSString *eventId) {
                
                NSAssert(nil != eventId, @"Cannot set up intial test conditions");
                
                sentMessageEventID = eventId;
                
                checkEventIDs();
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        }];
        
    }];
}


- (void)testListenerForRoomMessageLiveEvents
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;

        __block NSString *sentMessageEventID;
        __block NSString *receivedMessageEventID;
        
        void (^checkEventIDs)() = ^ void ()
        {
            if (sentMessageEventID && receivedMessageEventID)
            {
                XCTAssertTrue([receivedMessageEventID isEqualToString:sentMessageEventID]);
                
                [expectation fulfill];
            }
        };
        
        // Register the listener for m.room.message.only
        [room listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage]
                                          onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
            
            XCTAssertEqual(direction, MXEventDirectionForwards);
            
            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);
                                              
            XCTAssertNotNil(event.eventId);
                                              
            receivedMessageEventID = event.eventId;
                                              
            checkEventIDs();
        }];
        
        // Populate a text message in parallel
        [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndThePublicRoom:nil readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {
            
            [bobRestClient sendTextMessageToRoom:roomId text:@"Hello listeners!" success:^(NSString *eventId) {
                
                NSAssert(nil != eventId, @"Cannot set up intial test conditions");
                
                sentMessageEventID = eventId;
                
                checkEventIDs();
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        }];
        
    }];
}

- (void)testLeave
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession2, MXRoom *room, XCTestExpectation *expectation) {
        
        mxSession = mxSession2;
        
        NSString *roomId = room.state.roomId;
        
        // This implicitly tests MXSession leaveRoom
        [room leave:^{
            
            MXRoom *room2 = [mxSession roomWithRoomId:roomId];
            
            XCTAssertNil(room2, @"The room must be no more part of the MXSession rooms");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testSetPowerLevelOfUser
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [mxSession start:^{
        } onServerSyncDone:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            [room listenToEventsOfTypes:@[kMXEventTypeStringRoomPowerLevels] onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

                XCTAssertEqual([room.state.powerLevels powerLevelOfUserWithUserID:aliceRestClient.credentials.userId], 36);

               [expectation fulfill];
            }];

            [room setPowerLevelOfUserWithUserID:aliceRestClient.credentials.userId powerLevel:36 success:^{

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)testPaginateBackMessagesCancel
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];

        [mxSession startWithMessagesLimit:0 onStoreDataReady:^{
        } onServerSyncDone:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];

            __block NSUInteger eventCount = 0;
            [room listenToEvents:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {

                eventCount++;
                XCTFail(@"We should not receive events. Received: %@", event);

            }];

            [room resetBackState];
            NSOperation *pagination = [room paginateBackMessages:100 complete:^() {

                XCTFail(@"The cancelled operation must not complete");
                [expectation fulfill];

            } failure:^(NSError *error) {
                XCTAssertEqual(eventCount, 0, "We should have received events in registerEventListenerForTypes");
                [expectation fulfill];
            }];

            XCTAssertNotNil(pagination);

            [pagination cancel];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end

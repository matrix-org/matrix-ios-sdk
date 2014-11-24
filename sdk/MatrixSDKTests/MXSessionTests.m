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

@interface MXSessionTests : XCTestCase
{
    MXSession *mxSession;
}
@end

@implementation MXSessionTests

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


- (void)testRecents
{
    [[MatrixSDKTestsData sharedData] doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *room_id, NSString *new_text_message_event_id, XCTestExpectation *expectation) {
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [mxSession start:^{
            
            NSArray *recents = [mxSession recents];
            
            XCTAssertGreaterThan(recents.count, 0, @"There must be at least one recent");
            
            MXEvent *myNewTextMessageEvent;
            for (MXEvent *event in recents)
            {
                XCTAssertNotNil(event.eventId, @"The event must have an event_id to be valid");
                
                if ([event.eventId isEqualToString:new_text_message_event_id])
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
    [[MatrixSDKTestsData sharedData]doMXRestClientTestWihBobAndSeveralRoomsAndMessages:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {

        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [mxSession start:^{
            
            NSArray *recents = [mxSession recents];
            
            XCTAssertGreaterThanOrEqual(recents.count, 5, @"There must be at least 5 recents");
            
            uint64_t prev_ts = ULONG_LONG_MAX;
            for (MXEvent *event in recents)
            {
                XCTAssertNotNil(event.eventId, @"The event must have an event_id to be valid");
                
                if (event.originServerTs)
                {
                    XCTAssertLessThanOrEqual(event.originServerTs, prev_ts, @"Events must be listed in antichronological order");
                    prev_ts = event.originServerTs;
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
    [[MatrixSDKTestsData sharedData]doMXRestClientTestWihBobAndSeveralRoomsAndMessages:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        
        // The listener must catch at least these events
        __block NSMutableArray *expectedEvents =
        [NSMutableArray arrayWithArray:@[
                                         kMXEventTypeStringRoomCreate,
                                         kMXEventTypeStringRoomMember,
                                         
                                         // Expect the 5 text messages created by doMXRestClientTestWithBobAndARoomWithMessages
                                         kMXEventTypeStringRoomMessage,
                                         kMXEventTypeStringRoomMessage,
                                         kMXEventTypeStringRoomMessage,
                                         kMXEventTypeStringRoomMessage,
                                         kMXEventTypeStringRoomMessage,
                                         ]];
        
        [mxSession listenToEvents:^(MXEvent *event, MXEventDirection direction, id customObject) {
            
            if (MXEventDirectionForwards == direction)
            {
                [expectedEvents removeObject:event.type];
                
                if (0 == expectedEvents.count)
                {
                    XCTAssert(YES, @"All expected events must be catch");
                    
                    [mxSession close];
                    mxSession = nil;
                    
                    [expectation fulfill];
                }
            }
            
        }];
        
        
        // Create a room with messages in parallel
        [mxSession start:^{
            
            [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:nil readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {
            }];
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)testListenerForRoomMessageOnly
{
    [[MatrixSDKTestsData sharedData]doMXRestClientTestWihBobAndSeveralRoomsAndMessages:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        
        // Listen to m.room.message only
        // We should not see events coming before (m.room.create, and all state events)
        [mxSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage]
                                            onEvent:^(MXEvent *event, MXEventDirection direction, id customObject) {
            
            if (MXEventDirectionForwards == direction)
            {
                XCTAssertEqual(event.eventType, MXEventTypeRoomMessage, @"We must receive only m.room.message event - Event: %@", event);
                
                [mxSession close];
                mxSession = nil;
                
                [expectation fulfill];
            }
            
        }];
        
        
        // Create a room with messages in parallel
        [mxSession start:^{
            
            [[MatrixSDKTestsData sharedData] doMXRestClientTestWithBobAndARoomWithMessages:nil readyToTest:^(MXRestClient *bobRestClient, NSString *room_id, XCTestExpectation *expectation) {
            }];
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)testListenerForSyncEvents
{
    [[MatrixSDKTestsData sharedData]doMXRestClientTestWihBobAndSeveralRoomsAndMessages:self readyToTest:^(MXRestClient *bobRestClient, XCTestExpectation *expectation) {
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        
        __block NSUInteger eventCount = 0;
        
        // Listen to events received during rooms state sync
        [mxSession listenToEvents:^(MXEvent *event, MXEventDirection direction, id customObject) {
                                     
                                     eventCount++;
                                     
                                     XCTAssertEqual(direction, MXEventDirectionSync);
                                     
                                 }];
        
        
        // Create a room with messages in parallel
        [mxSession start:^{
            
            XCTAssertGreaterThan(eventCount, 0);
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}

- (void)testPresenceLastActiveAgo
{
    // Make sure Alice and Bob have activities
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *room_id, XCTestExpectation *expectation) {
        
        [bobRestClient postTextMessageToRoom:room_id text:@"Hi Alice!" success:^(NSString *event_id) {
            
            [aliceRestClient postTextMessageToRoom:room_id text:@"Hi Bob!" success:^(NSString *event_id) {
                
                mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                
                // Start the session
                [mxSession start:^{
                    
                    NSArray *users = mxSession.users;
                    
                    XCTAssertNotNil(users);
                    XCTAssertGreaterThanOrEqual(users.count, 2, "mxBob must know at least mxBob and mxAlice");
                    
                    MXUser *mxAlice;
                    NSUInteger lastAliceActivity = -1;
                    for (MXUser *user in users)
                    {
                        if ([user.userId isEqualToString:bobRestClient.credentials.userId])
                        {
                            XCTAssertLessThan(user.lastActiveAgo, 1000, @"mxBob has just posted a message. lastActiveAgo should not exceeds 1s. Found: %ld", user.lastActiveAgo);
                        }
                        if ([user.userId isEqualToString:aliceRestClient.credentials.userId])
                        {
                            mxAlice = user;
                            lastAliceActivity = user.lastActiveAgo;
                            XCTAssertLessThan(user.lastActiveAgo, 1000, @"mxAlice has just posted a message. lastActiveAgo should not exceeds 1s. Found: %ld", user.lastActiveAgo);

                            // mxAlice has a displayname and avatar defined. They should be found in the presence event
                            XCTAssert([user.displayname isEqualToString:kMXTestsAliceDisplayName]);
                            XCTAssert([user.avatarUrl isEqualToString:kMXTestsAliceAvatarURL]);
                        }
                    }
                    
                    // Wait a bit before getting lastActiveAgo again
                    [NSThread sleepForTimeInterval:1.0];
                    
                    NSUInteger newLastAliceActivity = mxAlice.lastActiveAgo;
                    XCTAssertGreaterThanOrEqual(newLastAliceActivity, lastAliceActivity + 1000, @"MXUser.lastActiveAgo should auto increase");
                    
                    [expectation fulfill];
                    
                } failure:^(NSError *error) {
                    NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
                }];
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
            
        } failure:^(NSError *error) {
            NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
        }];
    }];
}


- (void)testListenerForPresence
{
    // Make sure Alice and Bob have activities
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *room_id, XCTestExpectation *expectation) {
        
        mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        
        __block MXSession *mxSession2 = mxSession;
        __block NSUInteger lastAliceActivity = -1;
        
        // Listen to m.presence only
        [mxSession listenToEventsOfTypes:@[kMXEventTypeStringPresence]
                                           onEvent:^(MXEvent *event, MXEventDirection direction, id customObject) {
                                               
                                               if (MXEventDirectionForwards == direction)
                                               {
                                                   XCTAssertEqual(event.eventType, MXEventTypePresence, @"We must receive only m.presence - Event: %@", event);
                                                   
                                                   MXPresenceEventContent *eventContent = [MXPresenceEventContent modelFromJSON:event.content];
                                                   XCTAssert([eventContent.userId isEqualToString:aliceRestClient.credentials.userId]);
                                                   
                                                   MXUser *mxAlice = [mxSession2 user:eventContent.userId];
                                                   
                                                   NSUInteger newLastAliceActivity = mxAlice.lastActiveAgo;
                                                   XCTAssertLessThan(newLastAliceActivity, lastAliceActivity, @"alice activity must be updated");
                                                   
                                                   [expectation fulfill];
                                               }
                                           }];
        
        // Start the session
        [mxSession start:^{
            
            // Get the last Alice activity before making her active again
            lastAliceActivity = [mxSession2 user:aliceRestClient.credentials.userId].lastActiveAgo;
            
            // Wait a bit before making her active again
            [NSThread sleepForTimeInterval:1.0];
            
            [aliceRestClient postTextMessageToRoom:room_id text:@"Hi Bob!" success:^(NSString *event_id) {
                
            } failure:^(NSError *error) {
                NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
            }];
        }
         failure:^(NSError *error) {
             NSAssert(NO, @"Cannot set up intial test conditions - error: %@", error);
         }];
    }];
}

@end

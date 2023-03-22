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

#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"

#import "MXSession.h"
#import "MXFileStore.h"
#import "MXTools.h"
#import "MXSendReplyEventDefaultStringLocalizer.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXFileStore ()
- (NSString*)unreadRoomsFile;
- (NSString*)unreadFileForRoomsForBackup:(BOOL)backup;
@end


@interface MXRoomTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
}

@end

@implementation MXRoomTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
}

- (void)tearDown
{
    matrixSDKTestsData = nil;
    
    [super tearDown];
}


- (void)testListenerForAllLiveEvents
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        __block NSString *sentMessageEventID;
        __block NSString *receivedMessageEventID;
        
        void (^checkEventIDs)(void) = ^ void ()
        {
            if (sentMessageEventID && receivedMessageEventID)
            {
                XCTAssertTrue([receivedMessageEventID isEqualToString:sentMessageEventID]);
                
                [expectation fulfill];
            }
        };
        
        // Register the listener
        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            [liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                XCTAssertEqual(direction, MXTimelineDirectionForwards);

                XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);

                XCTAssertNotNil(event.eventId);

                receivedMessageEventID = event.eventId;

                checkEventIDs();
            }];
        }];
        
        // Populate a text message in parallel
        [matrixSDKTestsData doMXRestClientTestWithBobAndThePublicRoom:nil readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {
            
            [bobRestClient sendTextMessageToRoom:roomId threadId:nil text:@"Hello listeners!" success:^(NSString *eventId) {
                
                NSAssert(nil != eventId, @"Cannot set up intial test conditions");
                
                sentMessageEventID = eventId;
                
                checkEventIDs();
                
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
        
    }];
}


- (void)testListenerForRoomMessageLiveEvents
{
    [matrixSDKTestsData doMXSessionTestWithBobAndThePublicRoom:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        __block NSString *sentMessageEventID;
        __block NSString *receivedMessageEventID;
        
        void (^checkEventIDs)(void) = ^ void (void)
        {
            if (sentMessageEventID && receivedMessageEventID)
            {
                XCTAssertTrue([receivedMessageEventID isEqualToString:sentMessageEventID]);
                
                [expectation fulfill];
            }
        };
        
        // Register the listener for m.room.message.only
        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage]
                                        onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                                            XCTAssertEqual(direction, MXTimelineDirectionForwards);

                                            XCTAssertEqual(event.eventType, MXEventTypeRoomMessage);

                                            XCTAssertNotNil(event.eventId);

                                            receivedMessageEventID = event.eventId;

                                            checkEventIDs();
                                        }];
        }];
        
        // Populate a text message in parallel
        [matrixSDKTestsData doMXRestClientTestWithBobAndThePublicRoom:nil readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation2) {
            
            [bobRestClient sendTextMessageToRoom:roomId threadId:nil text:@"Hello listeners!" success:^(NSString *eventId) {
                
                NSAssert(nil != eventId, @"Cannot set up intial test conditions");
                
                sentMessageEventID = eventId;
                
                checkEventIDs();
                
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
        
    }];
}

- (void)testLeave
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        NSString *roomId = room.roomId;

        __block MXMembership lastKnownMembership = MXMembershipUnknown;
        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                lastKnownMembership = liveTimeline.state.membership;
            }];
        }];
        
        // This implicitly tests MXSession leaveRoom
        [room leave:^{

            XCTAssertEqual(lastKnownMembership, MXMembershipLeave, @"MXMembershipLeave must have been received before killing the MXRoom object");

            MXRoom *room2 = [mxSession roomWithRoomId:roomId];
            XCTAssertNil(room2, @"The room must be no more part of the MXSession rooms");

            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testIgnoreInviteSender
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobClient, NSString *roomId, XCTestExpectation *expectation) {

        [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceClient, XCTestExpectation *expectation2) {

            MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceClient];
            [matrixSDKTestsData retain:mxSession];

            [bobClient inviteUser:aliceClient.credentials.userId toRoom:roomId success:^{
                [mxSession startWithSyncFilter:[MXFilterJSONModel syncFilterWithMessageLimit:0]
                              onServerSyncDone:^{

                    MXRoom *room = [mxSession roomWithRoomId:roomId];
                    XCTAssertEqual(mxSession.ignoredUsers.count, 0);
                    XCTAssertEqual([mxSession isUserIgnored:bobClient.credentials.userId], NO);
                    
                    // Listen to mxSession.ignoredUsers changes where the successful assertion happens
                    [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionIgnoredUsersDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull notif) {
                        if (notif.object == mxSession)
                        {
                            XCTAssertEqual(mxSession.ignoredUsers.count, 1);
                            XCTAssertEqual([mxSession isUserIgnored:bobClient.credentials.userId], YES);

                            [expectation fulfill];
                        }
                    }];
                    
                    [room ignoreInviteSender:nil failure:^(NSError *error) {
                        XCTFail(@"Failed to ignore invite sender - NSError: %@", error);
                        [expectation fulfill];
                    }];

                } failure:^(NSError *error) {;
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}

- (void)testJoin
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        [matrixSDKTestsData doMXRestClientTestWithAlice:nil readyToTest:^(MXRestClient *aliceRestClient, XCTestExpectation *expectation2) {

            MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
            [matrixSDKTestsData retain:mxSession];

            [bobRestClient inviteUser:aliceRestClient.credentials.userId toRoom:roomId success:^{


                [mxSession startWithSyncFilter:[MXFilterJSONModel syncFilterWithMessageLimit:0]
                              onServerSyncDone:^{

                    MXRoom *room = [mxSession roomWithRoomId:roomId];

                    XCTAssertEqual(room.summary.membership, MXMembershipInvite);
                    XCTAssertEqual(room.summary.membersCount.members, 2, @"The room state information is limited while the room is joined");

                    [room join:^{

                        XCTAssertEqual(room.summary.membership, MXMembershipJoin);
                        XCTAssertEqual(room.summary.membersCount.members, 2, @"The room state must be fully known (after an initialSync on the room");

                        [expectation fulfill];

                    } failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];


                } failure:^(NSError *error) {;
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}

- (void)testSetPowerLevelOfUser
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];
        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomPowerLevels] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual([liveTimeline.state.powerLevels powerLevelOfUserWithUserID:aliceRestClient.credentials.userId], 36);

                    [expectation fulfill];
                }];
            }];

            [room setPowerLevelOfUserWithUserID:aliceRestClient.credentials.userId powerLevel:36 success:^{

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testPaginateBackMessagesCancel
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];

        [mxSession startWithSyncFilter:[MXFilterJSONModel syncFilterWithMessageLimit:0] onServerSyncDone:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];

            __block NSUInteger eventCount = 0;
            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                [liveTimeline listenToEvents:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    eventCount++;
                    XCTFail(@"We should not receive events. Received: %@", event);
                    [expectation fulfill];

                }];

                [liveTimeline resetPagination];
                MXHTTPOperation *pagination = [liveTimeline paginate:100 direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^() {

                    XCTFail(@"The cancelled operation must not complete");
                    [expectation fulfill];

                } failure:^(NSError *error) {
                    XCTAssertEqual(eventCount, 0, "We should have received events in registerEventListenerForTypes");
                    [expectation fulfill];
                }];

                XCTAssertNotNil(pagination);

                [pagination cancel];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testTypingUsersNotifications
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndARoom:self readyToTest:^(MXRestClient *bobRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            XCTAssertEqual(room.typingUsers.count, 0);

            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringTypingNotification] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(room.typingUsers.count, 1);
                    XCTAssertEqualObjects(room.typingUsers[0], bobRestClient.credentials.userId);

                    [expectation fulfill];
                }];
            }];

            [room sendTypingNotification:YES timeout:30000 success:^{

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testAddAndRemoveTag
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        NSString *tag = @"aTag";
        NSString *order = @"0.5";

        __block NSUInteger tagEventUpdata = 0;

        // Wait for the m.tag event to get the room tags update
        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomTag] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                if (++tagEventUpdata == 1)
                {
                    // This event is fired after the [room addTag:] request
                    MXRoomTag *roomTag = room.accountData.tags[tag];

                    XCTAssertNotNil(roomTag);
                    XCTAssertEqualObjects(roomTag.name, tag);
                    XCTAssertEqualObjects(roomTag.order, order);

                    [room removeTag:tag success:nil failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];
                }
                else if (tagEventUpdata == 2)
                {
                    // This event is fired after the [room removeTag:] request
                    XCTAssertNotNil(room.accountData.tags);
                    XCTAssertEqual(room.accountData.tags.count, 0);

                    [expectation fulfill];
                }
            }];

        }];

        // Do the test
        [room addTag:tag withOrder:order success:nil failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testReplaceTag
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {

        NSString *tag = @"aTag";
        NSString *order = @"0.5";
        NSString *newTag = @"newTag";
        NSString *newTagOrder = nil;

        // Wait for the m.tag event that corresponds to "newTag"
        [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
            [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomTag] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                MXRoomTag *newRoomTag = room.accountData.tags[newTag];
                if (newRoomTag)
                {
                    XCTAssertNotNil(newRoomTag);
                    XCTAssertEqualObjects(newRoomTag.name, newTag);
                    XCTAssertEqualObjects(newRoomTag.order, newTagOrder);

                    [expectation fulfill];
                }
            }];
        }];

        // Prepare initial condition: have a tag
        [room addTag:tag withOrder:order success:^{

            // Do the test
            [room replaceTag:tag byTag:newTag withOrder:newTagOrder success:nil failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testTagEvent
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for tagged events" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession start:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];
            
            // Wait for the m.tagged_events event
            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringTaggedEvents] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                    
                    XCTAssertEqual(event.eventType, MXEventTypeTaggedEvents);
                    
                    MXTaggedEventInfo* taggedEventInfo = [room.accountData getTaggedEventInfo:new_text_message_eventId withTag:kMXTaggedEventFavourite];
                    XCTAssertNotNil(taggedEventInfo);
                    
                    [expectation fulfill];
                }];
            }];
            
            [bobRestClient eventWithEventId:new_text_message_eventId success:^(MXEvent *event) {
                
                [room tagEvent:event withTag:kMXTaggedEventFavourite andKeywords:nil success:nil failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testUntagEvent
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for tagged events" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession start:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];
            __block MXEvent *taggedEvent;
            
            // Wait for the m.tagged_events event
            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringTaggedEvents] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                    
                    XCTAssertEqual(event.eventType, MXEventTypeTaggedEvents);
                    
                    MXTaggedEventInfo* taggedEventInfo = [room.accountData getTaggedEventInfo:new_text_message_eventId withTag:kMXTaggedEventFavourite];
                    
                    if (taggedEventInfo)
                    {
                        [room untagEvent:taggedEvent withTag:kMXTaggedEventFavourite success:nil failure:^(NSError *error) {
                            XCTFail(@"The request should not fail - NSError: %@", error);
                            [expectation fulfill];
                        }];
                    }
                    else
                    {
                        XCTAssertNil(taggedEventInfo);
                        
                        [expectation fulfill];
                    }
                }];
            }];
            
            [bobRestClient eventWithEventId:new_text_message_eventId success:^(MXEvent *event) {
                
                [room tagEvent:event withTag:kMXTaggedEventFavourite andKeywords:nil success:^{
                    taggedEvent = event;
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testGetTaggedEvent
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for tagged events" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {
        
        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession start:^{
            
            MXRoom *room = [mxSession roomWithRoomId:roomId];
            __block MXEvent *taggedEvent;
            
            // Wait for the m.tagged_events event
            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringTaggedEvents] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
                    
                    XCTAssertEqual(event.eventType, MXEventTypeTaggedEvents);
                    
                    [bobRestClient getTaggedEvents:roomId success:^(MXTaggedEvents *taggedEvents) {
                        XCTAssertNotNil(taggedEvents);
                        
                        NSDictionary *dictEventInfo = taggedEvents.tags[kMXTaggedEventFavourite][taggedEvent.eventId];
                        XCTAssertNotNil(dictEventInfo);
                        
                        MXTaggedEventInfo *taggedEventInfo;
                        MXJSONModelSetMXJSONModel(taggedEventInfo, MXTaggedEventInfo, dictEventInfo);
                        XCTAssertNotNil(taggedEventInfo);
                        
                        XCTAssertEqual(taggedEvent.originServerTs, taggedEventInfo.originServerTs);
                        [expectation fulfill];
                    } failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];
                }];
            }];
            
            [bobRestClient eventWithEventId:new_text_message_eventId success:^(MXEvent *event) {
                
                [room tagEvent:event withTag:kMXTaggedEventFavourite andKeywords:nil success:^{
                    taggedEvent = event;
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testRoomDirectoryVisibilityProvidedByInitialSync
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        [bobRestClient setRoomDirectoryVisibility:roomId directoryVisibility:kMXRoomDirectoryVisibilityPublic success:^{

            MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
            [matrixSDKTestsData retain:mxSession];
            
            [mxSession start:^{

                MXRoom *room = [mxSession roomWithRoomId:roomId];

                [room directoryVisibility:^(MXRoomDirectoryVisibility directoryVisibility) {

                    XCTAssertNotNil(directoryVisibility);
                    XCTAssertEqualObjects(directoryVisibility, kMXRoomDirectoryVisibilityPublic, @"The room directory visibility is wrong");

                    [expectation fulfill];

                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

- (void)tesRoomDirectoryVisibilityLive
{
    [matrixSDKTestsData doMXRestClientTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXRestClient *bobRestClient, NSString *roomId, NSString *new_text_message_eventId, XCTestExpectation *expectation) {

        MXRestClient *bobRestClient2 = bobRestClient;

        MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient2];
        [matrixSDKTestsData retain:mxSession];
        
        [mxSession start:^{

            MXRoom *room = [mxSession roomWithRoomId:roomId];

            [room directoryVisibility:^(MXRoomDirectoryVisibility directoryVisibility) {

                XCTAssertNotNil(directoryVisibility);
                XCTAssertEqualObjects(directoryVisibility, kMXRoomDirectoryVisibilityPrivate, @"The room directory visibility is wrong");


                // Change the directory visibility
                [bobRestClient setRoomDirectoryVisibility:roomId directoryVisibility:kMXRoomDirectoryVisibilityPublic success:^{

                    [room directoryVisibility:^(MXRoomDirectoryVisibility directoryVisibility) {

                        XCTAssertNotNil(directoryVisibility);
                        XCTAssertEqualObjects(directoryVisibility, kMXRoomDirectoryVisibilityPublic, @"The room directory visibility is wrong");

                        [expectation fulfill];

                    } failure:^(NSError *error) {
                        XCTFail(@"The request should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];

                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"The request should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
    }];
}

- (void)testSendReplyToTextMessage
{
    NSString *firstMessage = @"**First message!**";
    NSString *firstFormattedMessage = @"<p><strong>First message!</strong></p>";
    
    NSString *secondMessageReplyToFirst = @"**Reply to first message**";
    NSString *secondMessageFormattedReplyToFirst = @"<p><strong>Reply to first message</strong></p>";
    
    NSString *expectedSecondEventBodyStringFormat = @"> <%@> **First message!**\n\n**Reply to first message**";
    NSString *expectedSecondEventFormattedBodyStringFormat = @"<mx-reply><blockquote><a href=\"%@\">In reply to</a> <a href=\"%@\">%@</a><br><p><strong>First message!</strong></p></blockquote></mx-reply><p><strong>Reply to first message</strong></p>";
    
    NSString *thirdMessageReplyToSecond = @"**Reply to second message**";
    NSString *thirdMessageFormattedReplyToSecond = @"<p><strong>Reply to second message</strong></p>";
    
    NSString *expectedThirdEventBodyStringFormat = @"> <%@> **Reply to first message**\n\n**Reply to second message**";
    NSString *expectedThirdEventFormattedBodyStringFormat = @"<mx-reply><blockquote><a href=\"%@\">In reply to</a> <a href=\"%@\">%@</a><br><p><strong>Reply to first message</strong></p></blockquote></mx-reply><p><strong>Reply to second message</strong></p>";
    
    MXSendReplyEventDefaultStringLocalizer *defaultStringLocalizer = [MXSendReplyEventDefaultStringLocalizer new];
    
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        __block NSUInteger messageCount = 0;
        
        // Listen to messages
        [room listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {
            messageCount++;
            
            if (messageCount == 1)
            {
                __block MXEvent *localEchoEvent = nil;
                
                // Reply to first message
                [room sendReplyToEvent:event withTextMessage:secondMessageReplyToFirst formattedTextMessage:secondMessageFormattedReplyToFirst stringLocalizer:defaultStringLocalizer threadId:nil localEcho:&localEchoEvent success:^(NSString *eventId) {
                    MXLogDebug(@"Send reply to first message with success");
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
                XCTAssertNotNil(localEchoEvent);
                
                NSString *roomId = room.roomId;
                NSString *firstEventId = event.eventId;
                NSString *firstEventSender = event.sender;
                
                NSString *secondEventBody = localEchoEvent.content[kMXMessageBodyKey];
                NSString *secondEventFormattedBody = localEchoEvent.content[@"formatted_body"];
                NSString *secondEventRelatesToEventId = localEchoEvent.content[kMXEventRelationRelatesToKey][kMXEventContentRelatesToKeyInReplyTo][kMXEventContentRelatesToKeyEventId];

                NSString *permalinkToUser = [MXTools permalinkToUserWithUserId:firstEventSender];
                NSString *permalinkToEvent = [MXTools permalinkToEvent:firstEventId inRoom:roomId];

                NSString *expectedSecondEventBody = [NSString stringWithFormat:expectedSecondEventBodyStringFormat, firstEventSender];
                NSString *expectedSecondEventFormattedBody = [NSString stringWithFormat:expectedSecondEventFormattedBodyStringFormat, permalinkToEvent, permalinkToUser, firstEventSender];

                XCTAssertEqualObjects(secondEventBody, expectedSecondEventBody);
                XCTAssertEqualObjects(secondEventFormattedBody, expectedSecondEventFormattedBody);
                XCTAssertEqualObjects(firstEventId, secondEventRelatesToEventId);
            }
            else if (messageCount == 2)
            {
                __block MXEvent *localEchoEvent = nil;
                
                // Reply to second message, which was also a reply
                [room sendReplyToEvent:event withTextMessage:thirdMessageReplyToSecond formattedTextMessage:thirdMessageFormattedReplyToSecond stringLocalizer:defaultStringLocalizer threadId:nil localEcho:&localEchoEvent success:^(NSString *eventId) {
                    MXLogDebug(@"Send reply to second message with success");
                } failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
                
                XCTAssertNotNil(localEchoEvent);
                
                NSString *roomId = room.roomId;
                NSString *secondEventId = event.eventId;
                NSString *secondEventSender = event.sender;
                
                NSString *thirdEventBody = localEchoEvent.content[kMXMessageBodyKey];
                NSString *thirdEventFormattedBody = localEchoEvent.content[@"formatted_body"];
                NSString *thirdEventRelatesToEventId = localEchoEvent.content[kMXEventRelationRelatesToKey][kMXEventContentRelatesToKeyInReplyTo][kMXEventContentRelatesToKeyEventId];
                
                NSString *permalinkToUser = [MXTools permalinkToUserWithUserId:secondEventSender];
                NSString *permalinkToEvent = [MXTools permalinkToEvent:secondEventId inRoom:roomId];
                
                NSString *expectedThirdEventBody = [NSString stringWithFormat:expectedThirdEventBodyStringFormat, secondEventSender];
                NSString *expectedThirdEventFormattedBody = [NSString stringWithFormat:expectedThirdEventFormattedBodyStringFormat, permalinkToEvent, permalinkToUser, secondEventSender];
                
                XCTAssertEqualObjects(thirdEventBody, expectedThirdEventBody);
                XCTAssertEqualObjects(thirdEventFormattedBody, expectedThirdEventFormattedBody);
                XCTAssertEqualObjects(secondEventId, thirdEventRelatesToEventId);
            }
            else
            {
                [expectation fulfill];
            }
        }];
        
        // Send first message
        [room sendTextMessage:firstMessage formattedText:firstFormattedMessage threadId:nil localEcho:nil success:^(NSString *eventId) {
            MXLogDebug(@"Send first message with success");
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testUpgrade
{
    [matrixSDKTestsData doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        NSString *newRoomVersion = @"9";
        
        [mxSession.matrixRestClient upgradeRoomWithId:room.roomId to:newRoomVersion success:^(NSString *replacementRoomId) {
            
            XCTAssertNotEqual(room.roomId, replacementRoomId, @"Replacement room ID (%@) must be different from initial room ID (%@)", replacementRoomId, room.roomId);
            
            MXRoom *replacementRoom = [mxSession roomWithRoomId:replacementRoomId];
            XCTAssertNotNil(replacementRoom, "Cannot find replacement room");
            
            if (replacementRoom)
            {
                [replacementRoom state:^(MXRoomState *roomState) {
                    MXEvent *createEvent = [roomState stateEventsWithType:kMXEventTypeStringRoomCreate].lastObject;
                    XCTAssertNotNil(createEvent, "Cannot find create event");
                    
                    NSDictionary<NSString*, id> *wireContent = createEvent.wireContent;
                    XCTAssert([wireContent[@"creator"] isEqualToString:mxSession.myUserId]);
                    XCTAssert([wireContent[@"room_version"] isEqualToString:newRoomVersion]);
                    XCTAssert([wireContent[@"predecessor"][@"room_id"] isEqualToString:room.roomId]);
                    
                    [expectation fulfill];
                }];
            }
            else
            {
                [expectation fulfill];
            }
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testMarkUnread
{
    
    [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        MXSession *bobSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:bobSession];
        
        MXFileStore *store = [[MXFileStore alloc] init];
        
        [bobSession setStore:store success:^{
            [bobSession start:^{
                MXRoom *room = [bobSession roomWithRoomId:roomId];
                XCTAssertNotNil(room, @"the room should not be nil");
                [room setUnread];
                XCTAssert([room isMarkedAsUnread], @"the room should be marked as unread");
                [room resetUnread];
                XCTAssertFalse([room isMarkedAsUnread], @"the room should not be marked as unread");
                [expectation fulfill];
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

/**
 Check mark unread functionality with a new events
 
 - Have Alice and Bob in a room
 - Bob mark the room as unread
 - Alice send a new message to Bob
 - Bob's room should be unmarked as unread because a new lastmessage is received.
 */
- (void)testMarkUnreadWithMessage
{
    
    [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {
        
        MXSession *bobSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        MXSession *aliceSession = [[MXSession alloc] initWithMatrixRestClient:aliceRestClient];
        
        [matrixSDKTestsData retain:bobSession];
        
        MXFileStore *store = [[MXFileStore alloc] init];
        
        [bobSession setStore:store success:^{
            [bobSession start:^{
                MXRoom *room = [bobSession roomWithRoomId:roomId];
                XCTAssertNotNil(room, @"the room should not be nil");
                [room setUnread];
                XCTAssert([room isMarkedAsUnread], @"the room should be marked as unread");
                
                [room listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent * _Nonnull event, MXTimelineDirection direction, MXRoomState * _Nullable roomState) {
                    
                    dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, 100);
                    dispatch_after(delayTime, dispatch_get_main_queue(), ^(void) {
                        XCTAssertFalse([room isMarkedAsUnread], @"the room should not be marked as unread");
                        [expectation fulfill];
                    });
                }];

                MXFileStore *aliceStore = [[MXFileStore alloc] init];
                [aliceSession setStore:aliceStore success:^{
                    [aliceSession start:^{
                        MXRoom *aliceRoom = [aliceSession roomWithRoomId:roomId];
                        [aliceRoom sendTextMessage:@"Hello" threadId:nil success:^(NSString *eventId) {
                            [aliceSession close];
                                                } failure:^(NSError *error) {
                                                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                                    [expectation fulfill];
                                                }];
                                        } failure:^(NSError *error) {
                                            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                            [expectation fulfill];
                                        }];
                                } failure:^(NSError *error) {
                                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                    [expectation fulfill];
                                }];
            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Test migration of the MXFileStore unread rooms file that was at a bad location.
// - Have a Bob session with an unread room
// - Close that session
// - Reopen a Bob session (it simulates an app restart)
// -> The room should be still unread, meaning the migration went as expected
// TODO: Delete this test when removing the unreadFileForRoomsForBackup() method
- (void)testUnreadRoomsFileMigration
{
    // - Have a Bob session with an unread room
    MXFileStore *store = [MXFileStore new];
    [matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:store readyToTest:^(MXSession *bobSession, MXRoom *room, XCTestExpectation *expectation) {
        [room setUnread];
        
        // - Close that session
        NSString *roomId = room.roomId;
        MXRestClient *bobRestClient = bobSession.matrixRestClient;
        NSString *wrongFile = [store unreadFileForRoomsForBackup:NO];
        NSString *goodFile = [store unreadRoomsFile];
        [bobSession close];
        
        // - Move the unread rooms file to the previous wrong location
        [[NSFileManager defaultManager] moveItemAtPath:goodFile toPath:wrongFile error:nil];
        
        // - Reopen a Bob session (it simulates an app restart)
        MXSession *bobSession2 = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [self->matrixSDKTestsData retain:bobSession2];
        [bobSession2 setStore:[[MXFileStore alloc] init] success:^{
            
            // -> The room should be still unread, meaning the migration went as expected
            MXRoom *room = [bobSession2 roomWithRoomId:roomId];
            XCTAssert([room isMarkedAsUnread], @"the room should still be marked as unread");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end

#pragma clang diagnostic pop

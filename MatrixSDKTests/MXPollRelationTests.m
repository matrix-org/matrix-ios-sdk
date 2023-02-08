// 
// Copyright 2021 The Matrix.org Foundation C.I.C
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

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"

#import "MXFileStore.h"
#import "MXEventRelations.h"
#import "MXEventReferenceChunk.h"

#import "MXEventContentPollStart.h"

@interface MXPollRelationTests : XCTestCase

@property (nonatomic, strong) MatrixSDKTestsData *matrixSDKTestsData;
    
@property (nonatomic, strong) MatrixSDKTestsE2EData *matrixSDKTestsE2EData;

@end

@implementation MXPollRelationTests

- (void)setUp
{
    [super setUp];

    self.matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    self.matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:self.matrixSDKTestsData];
}

- (void)tearDown
{
    self.matrixSDKTestsData = nil;
    self.matrixSDKTestsE2EData = nil;
    
    [super tearDown];
}

- (void)testBobClosesPollWithOneAnswer
{
    [self createScenarioForBob:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, MXEvent *pollStartEvent, MXEventContentPollStart *pollStartContent) {
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [mxSession.aggregations referenceEventsForEvent:pollStartEvent.eventId inRoom:room.roomId from:nil limit:-1 success:^(MXAggregationPaginatedResponse *paginatedResponse) {
                XCTAssertNil(paginatedResponse.nextBatch);
                XCTAssertEqual(paginatedResponse.chunk.count, 0);
                
                [room sendPollResponseForEvent:pollStartEvent withAnswerIdentifiers:@[pollStartContent.answerOptions.firstObject.uuid] threadId:nil localEcho:nil success:^(NSString *eventId) {
                    [room sendPollEndForEvent:pollStartEvent threadId:nil localEcho:nil success:^(NSString *eventId) {
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                            [mxSession.aggregations referenceEventsForEvent:pollStartEvent.eventId inRoom:room.roomId from:nil limit:-1 success:^(MXAggregationPaginatedResponse *paginatedResponse) {
                                XCTAssertNil(paginatedResponse.nextBatch);
                                XCTAssertEqual(paginatedResponse.chunk.count, 2);
                                MXEvent* pollEndedEvent = paginatedResponse.chunk.lastObject;
                                XCTAssertTrue([pollEndedEvent.content[kMXMessageContentKeyExtensibleTextMSC1767] isEqual:@"Ended poll"]);
                                
                                [expectation fulfill];
                            } failure:^(NSError *error) {
                                XCTFail(@"The operation should not fail - NSError: %@", error);
                                [expectation fulfill];
                            }];
                        });
                    } failure:^(NSError *error) {
                        XCTFail(@"The operation should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];
                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        });
    }];
}

// Pagination on relations is not implemented on the backend.
// Make sure that's still the case.
- (void)testNoPollRelationPagination
{
    NSUInteger totalAnswers = 100;
    
    [self createScenarioForBob:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, MXEvent *pollStartEvent, MXEventContentPollStart *pollStartContent) {
        dispatch_group_t dispatchGroup = dispatch_group_create();
        for (NSUInteger i = 0; i < totalAnswers; i++) {
            dispatch_group_enter(dispatchGroup);
            [room sendPollResponseForEvent:pollStartEvent withAnswerIdentifiers:@[pollStartContent.answerOptions.firstObject.uuid] threadId:nil localEcho:nil success:^(NSString *eventId) {
                dispatch_group_leave(dispatchGroup);
            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        }
        
        dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
            [room sendPollEndForEvent:pollStartEvent threadId:nil localEcho:nil success:^(NSString *eventId) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    [mxSession.aggregations referenceEventsForEvent:pollStartEvent.eventId inRoom:room.roomId from:nil limit:-1 success:^(MXAggregationPaginatedResponse *paginatedResponse) {
                        XCTAssertEqual(paginatedResponse.chunk.count, totalAnswers + 1);
                        [expectation fulfill];
                    } failure:^(NSError *error) {
                        XCTFail(@"The operation should not fail - NSError: %@", error);
                        [expectation fulfill];
                    }];
                });
            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        });
    }];
}

- (void)testBobAndAliceAnswer
{
    [self createScenarioForBobAndAlice:^(MXSession *bobSession, MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation, NSString *pollStartEventId, MXEventContentPollStart *pollStartContent) {
        
        dispatch_group_t dispatchGroup = dispatch_group_create();
        
        MXRoom *bobRoom = [bobSession roomWithRoomId:roomId];
        
        dispatch_group_enter(dispatchGroup);
        [bobSession eventWithEventId:pollStartEventId inRoom:roomId success:^(MXEvent *event) {
            [bobRoom sendPollResponseForEvent:event withAnswerIdentifiers:@[pollStartContent.answerOptions.firstObject.uuid] threadId:nil localEcho:nil success:^(NSString *eventId) {
                dispatch_group_leave(dispatchGroup);
            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
        
        MXRoom *aliceRoom = [aliceSession roomWithRoomId:roomId];
        
        dispatch_group_enter(dispatchGroup);
        [aliceSession eventWithEventId:pollStartEventId inRoom:roomId success:^(MXEvent *event) {
            
            for (NSUInteger i = 0; i < 10; i++)
            {
                dispatch_group_enter(dispatchGroup);
                [aliceRoom sendPollResponseForEvent:event withAnswerIdentifiers:@[pollStartContent.answerOptions.lastObject.uuid] threadId:nil localEcho:nil success:^(NSString *eventId) {
                    dispatch_group_leave(dispatchGroup);
                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            }
            
            dispatch_group_leave(dispatchGroup);

        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
        
        dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [bobSession.aggregations referenceEventsForEvent:pollStartEventId inRoom:roomId from:nil limit:-1 success:^(MXAggregationPaginatedResponse *paginatedResponse) {
                    XCTAssertEqual(paginatedResponse.chunk.count, 11);
                    XCTAssertEqualObjects(paginatedResponse.chunk.firstObject.sender, bobSession.myUser.userId);
                    XCTAssertEqualObjects(paginatedResponse.chunk.lastObject.sender, aliceSession.myUser.userId);
                    [expectation fulfill];
                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            });
        });
    }];
}

// - Create a room with a poll in it
// - Add enough messages while the session in background to trigger a gappy sync
// - Add poll answers in the gap
- (void)testAnswerInAGappySync
{
    [self createScenarioForBobAndAlice:^(MXSession *bobSession, MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation, NSString *pollStartEventId, MXEventContentPollStart *pollStartContent) {
        
        // - Add enough messages while the session in background to trigger a gappy sync
        [bobSession pause];
        [self.matrixSDKTestsData for:bobSession.matrixRestClient andRoom:roomId sendMessages:10 testCase:self success:^{
            
            // - Add a poll answer in the gap
            MXRoom *aliceRoom = [aliceSession roomWithRoomId:roomId];
            [aliceSession eventWithEventId:pollStartEventId inRoom:roomId success:^(MXEvent *event) {
                [aliceRoom sendPollResponseForEvent:event withAnswerIdentifiers:@[pollStartContent.answerOptions.lastObject.uuid] threadId:nil localEcho:nil success:^(NSString *eventId) {
                    
                    [self.matrixSDKTestsData for:bobSession.matrixRestClient andRoom:roomId sendMessages:20 testCase:self success:^{
                        [bobSession start:^{
                            [bobSession.aggregations referenceEventsForEvent:pollStartEventId inRoom:roomId from:nil limit:-1 success:^(MXAggregationPaginatedResponse *paginatedResponse) {
                                XCTAssertEqual(paginatedResponse.chunk.count, 1);
                                XCTAssertEqualObjects(paginatedResponse.chunk.firstObject.sender, aliceSession.myUser.userId);
                                XCTAssertEqualObjects(paginatedResponse.chunk.firstObject.eventId, eventId);
                                [expectation fulfill];
                            } failure:^(NSError *error) {
                                XCTFail(@"The operation should not fail - NSError: %@", error);
                                [expectation fulfill];
                            }];
                        } failure:^(NSError *error) {
                            XCTFail(@"The operation should not fail - NSError: %@", error);
                            [expectation fulfill];
                        }];
                    }];
                } failure:^(NSError *error) {
                    XCTFail(@"The operation should not fail - NSError: %@", error);
                    [expectation fulfill];
                }];
            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        }];
    }];
}

#pragma mark - Private

- (void)createScenarioForBob:(void(^)(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation, MXEvent *pollStartEvent, MXEventContentPollStart *pollStartContent))readyToTest
{
    [self.matrixSDKTestsData doMXSessionTestWithBobAndARoom:self andStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *mxSession, MXRoom *room, XCTestExpectation *expectation) {
        
        NSArray *answerOptions = @[[[MXEventContentPollStartAnswerOption alloc] initWithUUID:NSUUID.UUID.UUIDString text:@"First answer"],
                                   [[MXEventContentPollStartAnswerOption alloc] initWithUUID:NSUUID.UUID.UUIDString text:@"Second answer"]];
        
        MXEventContentPollStart *pollStartContent = [[MXEventContentPollStart alloc] initWithQuestion:@"Question"
                                                                                                 kind:kMXMessageContentKeyExtensiblePollKindUndisclosed
                                                                                        maxSelections:@(1)
                                                                                        answerOptions:answerOptions];
        
        [room sendPollStartWithContent:pollStartContent threadId:nil localEcho:nil success:^(NSString *pollStartEventId) {
            
            [mxSession.matrixRestClient eventWithEventId:pollStartEventId inRoom:room.roomId success:^(MXEvent *pollStartEvent) {
                
                MXEventContentPollStart *content = [MXEventContentPollStart modelFromJSON:pollStartEvent.content];
                
                XCTAssertEqualObjects(content.question, pollStartContent.question);
                XCTAssertEqualObjects(content.answerOptions.firstObject.text, pollStartContent.answerOptions.firstObject.text);
                XCTAssertEqualObjects(content.answerOptions.lastObject.text, pollStartContent.answerOptions.lastObject.text);
                
                readyToTest(mxSession, room, expectation, pollStartEvent, pollStartContent);
            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)createScenarioForBobAndAlice:(void(^)(MXSession *bobSession, MXSession *aliceSession, NSString *roomId, XCTestExpectation *expectation, NSString *pollStartEventId, MXEventContentPollStart *pollStartContent))readyToTest
{
    [self.matrixSDKTestsData doTestWithAliceAndBobInARoom:self aliceStore:[[MXMemoryStore alloc] init] bobStore:[[MXMemoryStore alloc] init] readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {
        
        MXRoom *room = [bobSession roomWithRoomId:roomId];
        
        NSArray *answerOptions = @[[[MXEventContentPollStartAnswerOption alloc] initWithUUID:NSUUID.UUID.UUIDString text:@"First answer"],
                                   [[MXEventContentPollStartAnswerOption alloc] initWithUUID:NSUUID.UUID.UUIDString text:@"Second answer"]];
        
        MXEventContentPollStart *pollStartContent = [[MXEventContentPollStart alloc] initWithQuestion:@"Question"
                                                                                                 kind:kMXMessageContentKeyExtensiblePollKindUndisclosed
                                                                                        maxSelections:@(1)
                                                                                        answerOptions:answerOptions];
        
        [room sendPollStartWithContent:pollStartContent threadId:nil localEcho:nil success:^(NSString *pollStartEventId) {
            
            [bobSession.matrixRestClient eventWithEventId:pollStartEventId inRoom:room.roomId success:^(MXEvent *pollStartEvent) {
                
                MXEventContentPollStart *content = [MXEventContentPollStart modelFromJSON:pollStartEvent.content];
                
                XCTAssertEqualObjects(content.question, pollStartContent.question);
                XCTAssertEqualObjects(content.answerOptions.firstObject.text, pollStartContent.answerOptions.firstObject.text);
                XCTAssertEqualObjects(content.answerOptions.lastObject.text, pollStartContent.answerOptions.lastObject.text);
                
                readyToTest(bobSession, aliceSession, roomId, expectation, pollStartEventId, pollStartContent);
            } failure:^(NSError *error) {
                XCTFail(@"The operation should not fail - NSError: %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"The operation should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end

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

@interface MXRoomDataTests : XCTestCase
{
}

@end

@implementation MXRoomDataTests

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)doMXRoomDataTestWithBobAndARoomWithMessages:(void (^)(MXRoomData *roomData, XCTestExpectation *expectation))readyToTest
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXSession *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        MXData *matrixData = [[MXData alloc] initWithMatrixSession:bobSession];
        
        
        [matrixData start:^{
            MXRoomData *roomData = [matrixData getRoomData:room_id];
            
            readyToTest(roomData, expectation);
            
        } failure:^(NSError *error) {
            
        }];
    }];
}


- (void)testMembers
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestInABobRoomAndANewTextMessage:self newTextMessage:@"This is a text message for recents" onReadyToTest:^(MXSession *bobSession, NSString *room_id, NSString *new_text_message_event_id, XCTestExpectation *expectation) {
        
        MXData *matrixData = [[MXData alloc] initWithMatrixSession:bobSession];
        [matrixData start:^{
            
            MXRoomData *roomData = [matrixData getRoomData:room_id];
            XCTAssertNotNil(roomData);
            
            NSArray *members = roomData.members;
            XCTAssertEqual(members.count, 1, "There must be only one member: mxBob, the creator");
            
            for (MXRoomMember *member in roomData.members)
            {
                XCTAssertTrue([member.user_id isEqualToString:bobSession.user_id], "This must be mxBob");
            }
            
            XCTAssertNotNil([roomData getMember:bobSession.user_id], @"Bob must be retrieved");
            
            XCTAssertNil([roomData getMember:@"NonExistingUserId"], @"getMember must return nil if the user does not exist");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testMessagesPropertyCopy
{
    [self doMXRoomDataTestWithBobAndARoomWithMessages:^(MXRoomData *roomData, XCTestExpectation *expectation) {
        
        NSArray *messagesBeforePagination = roomData.messages;
        
        XCTAssertEqual(messagesBeforePagination.count, 1, @"Just after initialSync, we should have 1 message");
        
        MXEvent *event = messagesBeforePagination[0];
        NSString *event_id = event.event_id;
        
        [roomData paginateBackMessages:50 success:^(NSArray *messages) {
            
            
            XCTAssertEqual(messagesBeforePagination.count, 1, @"roomData.messages is a copy property. messagesBeforePagination must not have changed");
            
            MXEvent *eventAfterPagination = messagesBeforePagination[0];
            
            XCTAssertTrue([eventAfterPagination.event_id isEqualToString:event_id], @"The only event must be the same as before the pagination action");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}


- (void)testPaginateBack
{
    [self doMXRoomDataTestWithBobAndARoomWithMessages:^(MXRoomData *roomData, XCTestExpectation *expectation) {
        
        NSArray *messagesBeforePagination = roomData.messages;
        
        [roomData paginateBackMessages:50 success:^(NSArray *messages) {
            
            NSArray *messagesAfterPagination = roomData.messages;
            
            XCTAssertEqual(messagesAfterPagination.count, messagesBeforePagination.count + messages.count, @"roomData.messages count must have increased by the number of new messages got by pagination");
            
            [expectation fulfill];
            
        } failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];
    }];
}

@end

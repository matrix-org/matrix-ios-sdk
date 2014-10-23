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

@interface MXEventTests : XCTestCase
{
    MXData *matrixData;
}

@end

@implementation MXEventTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    if (matrixData)
    {
        [matrixData close];
        matrixData = nil;
    }
    [super tearDown];
}


- (void)testIsState
{
    [[MatrixSDKTestsData sharedData] doMXSessionTestWithBobAndARoomWithMessages:self readyToTest:^(MXRestClient *bobSession, NSString *room_id, XCTestExpectation *expectation) {
        
        matrixData = [[MXData alloc] initWithMatrixSession:bobSession];
        
        [matrixData start:^{
            MXRoomData *roomData = [matrixData getRoomData:room_id];
            
            for (MXEvent *stateEvent in roomData.stateEvents)
            {
                XCTAssertTrue(stateEvent.isState, "All events in roomData.stateEvents must be states. stateEvent: %@", stateEvent);
            }
            
            for (MXEvent *message in roomData.messages)
            {
                if (message.eventType == MXEventTypeRoomMessage)
                {
                    XCTAssertFalse(message.isState, "Room messages are not states. message: %@", message);
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

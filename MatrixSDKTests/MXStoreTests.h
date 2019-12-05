/*
 Copyright 2015 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd

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

@interface MXStoreTests : XCTestCase
{
    MXSession *mxSession;

    // The current test expectation
    XCTestExpectation *expectation;
}

- (void)doTestWithStore:(id<MXStore>)store readyToTest:(void (^)(MXRoom *room))readyToTest;
- (void)doTestWithTwoUsersAndStore:(id<MXStore>)store readyToTest:(void (^)(MXRoom *room))readyToTest;
- (void)doTestWithStore:(id<MXStore>)store andMessagesLimit:(NSUInteger)messagesLimit readyToTest:(void (^)(MXRoom *room))readyToTest;

- (void)assertNoDuplicate:(NSArray*)events text:(NSString*)text;

- (void)checkEventExistsWithEventIdOfStore:(id<MXStore>)store;
- (void)checkEventWithEventIdOfStore:(id<MXStore>)store;
- (void)checkPaginateBack:(MXRoom*)room;
- (void)checkPaginateBackFilter:(MXRoom*)room;
- (void)checkPaginateBackOrder:(MXRoom*)room;
- (void)checkPaginateBackDuplicates:(MXRoom*)room;
- (void)checkSeveralPaginateBacks:(MXRoom*)room;
- (void)checkPaginateWithLiveEvents:(MXRoom*)room;
- (void)checkCanPaginateFromHomeServer:(MXRoom*)room;
- (void)checkCanPaginateFromMXStore:(MXRoom*)room;
- (void)checkLastMessageAfterPaginate:(MXRoom*)room;
- (void)checkPaginateWhenJoiningAgainAfterLeft:(MXRoom*)room;
- (void)checkLastMessageProfileChange:(MXRoom*)room;
- (void)checkLastMessageIgnoreProfileChange:(MXRoom*)room;
- (void)checkPaginateWhenReachingTheExactBeginningOfTheRoom:(MXRoom*)room;  // Test for https://matrix.org/jira/browse/SYN-162
- (void)checkRedactEvent:(MXRoom*)room;

// Tests that may not relevant for all implementations
- (void)checkUserDisplaynameAndAvatarUrl:(Class)mxStoreClass;
- (void)checkUpdateUserDisplaynameAndAvatarUrl:(Class)mxStoreClass;
- (void)checkMXSessionOnStoreDataReady:(Class)mxStoreClass;
- (void)checkRoomDeletion:(Class)mxStoreClass;
- (void)checkEventAge:(Class)mxStoreClass;
- (void)checkMXRoomPaginationToken:(Class)mxStoreClass;
- (void)checkMultiAccount:(Class)mxStoreClass;
- (void)checkRoomAccountDataTags:(Class)mxStoreClass;
- (void)checkRoomSummary:(Class)mxStoreClass;

@end


// Copyright 2026
// SPDX-License-Identifier: Apache-2.0

#import <XCTest/XCTest.h>
#import <MatrixSDK/MatrixSDK.h>

@interface MXSession (SlidingSyncPersistenceTests)
- (NSString *)slidingSyncPersistenceKey;
- (void)persistSlidingSyncState;
- (void)restoreSlidingSyncStateWithConfiguration:(MXSlidingSyncConfiguration *)configuration;
- (void)resetSlidingSyncStateForUnknownPosition;
@end

@interface MXSlidingSyncTests : XCTestCase
@end

@implementation MXSlidingSyncTests

- (void)testDefaultRequestUsesFastInitialWindowAndRequiredState
{
    MXSlidingSyncConfiguration *configuration = MXSlidingSyncConfiguration.defaultConfiguration;
    NSDictionary *request = [configuration requestDictionaryWithPosition:@"42"
                                                              connectionId:@"connection"
                                                                    ranges:@[@[@0, @49]]
                                                         roomSubscriptions:@[@"!deep:example.org"]
                                                                   timeout:30000
                                                               setPresence:@"online"];

    XCTAssertEqualObjects(request[@"pos"], @"42");
    XCTAssertEqualObjects(request[@"lists"][@"main"][@"ranges"], (@[@[@0, @49]]));
    XCTAssertEqualObjects(request[@"lists"][@"main"][@"timeline_limit"], @1);
    XCTAssertTrue(([request[@"lists"][@"main"][@"required_state"] containsObject:@[@"m.room.member", @"$ME"]]));
    XCTAssertNotNil(request[@"room_subscriptions"][@"!deep:example.org"]);
    XCTAssertTrue([request[@"extensions"][@"e2ee"][@"enabled"] boolValue]);
    XCTAssertTrue([request[@"extensions"][@"to_device"][@"enabled"] boolValue]);
}

- (void)testSimplifiedResponseAdaptsToLegacySyncPipeline
{
    NSDictionary *json = @{
        @"pos": @"99",
        @"lists": @{@"main": @{@"count": @1}},
        @"rooms": @{
            @"!room:example.org": @{
                @"membership": @"join",
                @"initial": @1,
                @"notification_count": @4,
                @"highlight_count": @2,
                @"bump_stamp": @123,
                @"required_state": @[@{@"type": @"m.room.name", @"state_key": @"", @"content": @{@"name": @"Room"}}],
                @"timeline": @[@{@"type": @"m.room.message", @"event_id": @"$event", @"sender": @"@alice:example.org", @"origin_server_ts": @1, @"content": @{@"msgtype": @"m.text", @"body": @"Hi"}}]
            }
        },
        @"extensions": @{
            @"to_device": @{@"next_batch": @"device-2", @"events": @[]},
            @"e2ee": @{@"device_lists": @{@"changed": @[@"@alice:example.org"], @"left": @[]}, @"device_one_time_keys_count": @{@"signed_curve25519": @3}},
            @"account_data": @{@"global": @[], @"rooms": @{}},
            @"receipts": @{@"rooms": @{}},
            @"typing": @{@"rooms": @{}}
        }
    };

    MXSlidingSyncResponse *response = [MXSlidingSyncResponse modelFromJSON:json];
    MXSyncResponse *legacy = [response legacySyncResponseForUserId:@"@me:example.org"];
    MXRoomSync *room = legacy.rooms.join[@"!room:example.org"];

    XCTAssertEqualObjects(response.position, @"99");
    XCTAssertEqual(response.lists[@"main"].count, 1u);
    XCTAssertEqual(room.timeline.events.count, 1u);
    XCTAssertEqual(room.unreadNotifications.notificationCount, 4u);
    XCTAssertEqual(room.unreadNotifications.highlightCount, 2u);
    XCTAssertEqualObjects(legacy.deviceOneTimeKeysCount[@"signed_curve25519"], @3);
}

- (void)testParsesEveryClassicListOperationForCompatibleServers
{
    NSDictionary *json = @{@"count": @4, @"ops": @[
        @{@"op": @"SYNC", @"range": @[@0, @1], @"room_ids": @[@"!a:x", @"!b:x"]},
        @{@"op": @"INSERT", @"index": @1, @"room_id": @"!c:x"},
        @{@"op": @"DELETE", @"index": @2},
        @{@"op": @"MOVE", @"from": @3, @"to": @0},
        @{@"op": @"INVALIDATE", @"range": @[@2, @3]}
    ]};
    MXSlidingSyncList *list = [MXSlidingSyncList modelFromJSON:json];
    XCTAssertEqual(list.operations.count, 5u);
    XCTAssertEqualObjects(list.operations[0].roomIds, (@[@"!a:x", @"!b:x"]));
    XCTAssertEqualObjects(list.operations[3].fromIndex, @3);
    XCTAssertEqualObjects(list.operations[3].toIndex, @0);
    XCTAssertEqualObjects(list.operations[4].range, (@[@2, @3]));
}

- (void)testNewSessionRestoresCommittedSlidingSyncStateAndExpandedRange
{
    MXCredentials *credentials = [[MXCredentials alloc] initWithHomeServer:@"https://example.org"
                                                                    userId:@"@restore:example.org"
                                                               accessToken:@"token"];
    MXRestClient *firstRestClient = [[MXRestClient alloc] initWithCredentials:credentials
                                          andOnUnrecognizedCertificateBlock:nil];
    MXSession *first = [[MXSession alloc] initWithMatrixRestClient:firstRestClient];
    NSString *persistenceKey = first.slidingSyncPersistenceKey;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:persistenceKey];
    [first setValue:@"pos-7" forKey:@"slidingSyncPosition"];
    [first setValue:@"conn-7" forKey:@"slidingSyncConnectionId"];
    [first setValue:@"device-7" forKey:@"slidingSyncToDevicePosition"];
    [first setValue:@[@"!a:example.org", @"!b:example.org", @"!c:example.org"] forKey:@"slidingSyncRoomOrder"];
    [first setValue:[@{@"!a:example.org": @30, @"!b:example.org": @20} mutableCopy] forKey:@"slidingSyncBumpStamps"];
    [first setValue:@120 forKey:@"slidingSyncTotalRoomCount"];
    [first persistSlidingSyncState];

    MXRestClient *restoredRestClient = [[MXRestClient alloc] initWithCredentials:credentials
                                             andOnUnrecognizedCertificateBlock:nil];
    MXSession *restored = [[MXSession alloc] initWithMatrixRestClient:restoredRestClient];
    MXMemoryStore *store = [MXMemoryStore new];
    MXRoomSummary *summary = [[MXRoomSummary alloc] initWithRoomId:@"!a:example.org" andMatrixSession:nil];
    [store.roomSummaryStore storeSummary:summary];
    XCTestExpectation *ready = [self expectationWithDescription:@"memory store ready"];
    [restored setStore:store success:^{
        MXSlidingSyncConfiguration *configuration = MXSlidingSyncConfiguration.defaultConfiguration;
        configuration.initialWindowSize = 2;
        [restored setValue:configuration forKey:@"slidingSyncConfiguration"];
        [restored restoreSlidingSyncStateWithConfiguration:configuration];

        XCTAssertEqualObjects([restored valueForKey:@"slidingSyncPosition"], @"pos-7");
        XCTAssertEqualObjects([restored valueForKey:@"slidingSyncConnectionId"], @"conn-7");
        XCTAssertEqualObjects([restored valueForKey:@"slidingSyncToDevicePosition"], @"device-7");
        XCTAssertEqualObjects(restored.slidingSyncRoomOrder, (@[@"!a:example.org", @"!b:example.org", @"!c:example.org"]));
        XCTAssertEqualObjects([restored valueForKey:@"slidingSyncBumpStamps"], (@{@"!a:example.org": @30, @"!b:example.org": @20}));
        XCTAssertEqualObjects([restored valueForKey:@"slidingSyncTotalRoomCount"], @120);
        XCTAssertEqualObjects([restored valueForKey:@"slidingSyncRangeEnd"], @2,
                              @"The next request must cover at least the previously loaded order");
        XCTAssertEqualObjects(configuration.extensions[@"to_device"][@"since"], @"device-7");
        XCTAssertEqual(restored.roomListState.loaded, 3u);
        XCTAssertEqual(restored.roomListState.total, 120u);
        [ready fulfill];
    } failure:^(NSError *error) {
        XCTFail(@"Cannot open memory store: %@", error);
        [ready fulfill];
    }];

    [self waitForExpectationsWithTimeout:2 handler:nil];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:persistenceKey];
}

- (void)testCacheClearAndUnknownPositionDiscardIncompatibleMetadata
{
    MXCredentials *credentials = [[MXCredentials alloc] initWithHomeServer:@"https://example.org"
                                                                    userId:@"@unknown:example.org"
                                                               accessToken:@"token"];
    MXRestClient *restClient = [[MXRestClient alloc] initWithCredentials:credentials
                                      andOnUnrecognizedCertificateBlock:nil];
    MXSession *session = [[MXSession alloc] initWithMatrixRestClient:restClient];
    NSString *persistenceKey = session.slidingSyncPersistenceKey;
    NSDictionary *persisted = @{
        @"position": @"stale-pos",
        @"connectionId": @"stale-conn",
        @"toDevicePosition": @"stale-device",
        @"roomOrder": @[@"!stale:example.org"],
        @"bumpStamps": @{@"!stale:example.org": @1},
        @"total": @1
    };
    [NSUserDefaults.standardUserDefaults setObject:persisted forKey:persistenceKey];

    XCTestExpectation *ready = [self expectationWithDescription:@"empty store ready"];
    [session setStore:[MXMemoryStore new] success:^{
        MXSlidingSyncConfiguration *configuration = MXSlidingSyncConfiguration.defaultConfiguration;
        [session setValue:configuration forKey:@"slidingSyncConfiguration"];
        [session restoreSlidingSyncStateWithConfiguration:configuration];
        XCTAssertNil([NSUserDefaults.standardUserDefaults objectForKey:persistenceKey]);
        XCTAssertNil([session valueForKey:@"slidingSyncPosition"]);
        XCTAssertTrue(session.slidingSyncRoomOrder.count == 0);

        [session setValue:@"accepted-pos" forKey:@"slidingSyncPosition"];
        [session setValue:@"accepted-conn" forKey:@"slidingSyncConnectionId"];
        [session setValue:@"accepted-device" forKey:@"slidingSyncToDevicePosition"];
        NSMutableDictionary *extensions = configuration.extensions.mutableCopy;
        NSMutableDictionary *toDevice = [extensions[@"to_device"] mutableCopy];
        toDevice[@"since"] = @"accepted-device";
        extensions[@"to_device"] = toDevice;
        configuration.extensions = extensions;
        [session persistSlidingSyncState];
        XCTAssertNotNil([NSUserDefaults.standardUserDefaults objectForKey:persistenceKey]);

        NSString *oldConnectionId = [session valueForKey:@"slidingSyncConnectionId"];
        [session resetSlidingSyncStateForUnknownPosition];
        XCTAssertNil([session valueForKey:@"slidingSyncPosition"]);
        XCTAssertNil([session valueForKey:@"slidingSyncToDevicePosition"]);
        XCTAssertNotEqualObjects([session valueForKey:@"slidingSyncConnectionId"], oldConnectionId);
        XCTAssertNil(configuration.extensions[@"to_device"][@"since"]);
        XCTAssertNil([NSUserDefaults.standardUserDefaults objectForKey:persistenceKey]);
        [ready fulfill];
    } failure:^(NSError *error) {
        XCTFail(@"Cannot open memory store: %@", error);
        [ready fulfill];
    }];

    [self waitForExpectationsWithTimeout:2 handler:nil];
}

@end

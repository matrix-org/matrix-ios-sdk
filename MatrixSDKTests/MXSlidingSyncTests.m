// Copyright 2026
// SPDX-License-Identifier: Apache-2.0

#import <XCTest/XCTest.h>
#import <MatrixSDK/MatrixSDK.h>

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

@end

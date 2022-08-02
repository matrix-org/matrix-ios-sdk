/*
 Copyright 2018 New Vector Ltd
 
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

#import "MXScanRealmInMemoryProvider.h"
#import "MXRealmEventScanStore.h"
#import "MXEventScanStore.h"
#import "MXEventScan.h"

static NSString* const kDefaultAntivirusServerDomain = @"matrix.org";

@interface MXEventScanStoreUnitTests : XCTestCase

@property (nonatomic, strong) id<MXScanRealmProvider> realmProvider;
@property (nonatomic, strong) id<MXEventScanStore> eventScanStore;

@end

@implementation MXEventScanStoreUnitTests

- (void)setUp
{
    [super setUp];
    
    id<MXScanRealmProvider> realmProvider = [[MXScanRealmInMemoryProvider alloc] initWithAntivirusServerDomain:kDefaultAntivirusServerDomain];
    self.eventScanStore = [[MXRealmEventScanStore alloc] initWithRealmProvider:realmProvider];
    self.realmProvider = realmProvider;
    [self.realmProvider deleteAllObjects];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testCreateEventScan
{
    NSString *eventId = @"123456igzeoijncvoiuhekaj:matrix.org";
    
    MXAntivirusScanStatus initialAntivirusScanStatus = MXAntivirusScanStatusInProgress;
    
    NSArray<NSString*>* mediaURLs = @[
                                      @"mxc://matrix.org/7398H34PHL3904U",
                                      @"mxc://matrix.org/7398H34PHL3904V"
                                      ];
    
    MXEventScan *eventScan = [self.eventScanStore createOrUpdateWithId:eventId initialAntivirusStatus:initialAntivirusScanStatus andMediaURLs:mediaURLs];
    
    XCTAssertNotNil(eventScan);
    XCTAssertEqualObjects(eventScan.eventId, eventId);
    XCTAssertEqual(eventScan.antivirusScanStatus, initialAntivirusScanStatus);
    XCTAssertNil(eventScan.antivirusScanDate);
    XCTAssert(eventScan.mediaScans.count == 2);
}

- (void)testCreateEventScanTwice
{
    NSString *eventId = @"123456igzeoijncvoiuhekaj:matrix.org";
    
    MXAntivirusScanStatus initialAntivirusScanStatus = MXAntivirusScanStatusInProgress;
    
    NSArray<NSString*>* mediaURLs = @[
                                      @"mxc://matrix.org/7398H34PHL3904U",
                                      @"mxc://matrix.org/7398H34PHL3904V"
                                      ];
    
    MXEventScan *eventScan1 = [self.eventScanStore createOrUpdateWithId:eventId initialAntivirusStatus:initialAntivirusScanStatus andMediaURLs:mediaURLs];
    MXEventScan *eventScan2 = [self.eventScanStore createOrUpdateWithId:eventId initialAntivirusStatus:initialAntivirusScanStatus andMediaURLs:mediaURLs];
    
    XCTAssertNotNil(eventScan1);
    XCTAssertNotNil(eventScan2);
    
    XCTAssertEqualObjects(eventScan1, eventScan2);
}

- (void)testFindEventScan
{
    NSString *eventId = @"123456igzeoijncvoiuhekaj:matrix.org";
    
    NSArray<NSString*>* mediaURLs = @[
                                      @"mxc://matrix.org/7398H34PHL3904U",
                                      @"mxc://matrix.org/7398H34PHL3904V"
                                      ];
    
    MXEventScan *insertedEventScan = [self.eventScanStore createOrUpdateWithId:eventId initialAntivirusStatus:MXAntivirusScanStatusUnknown andMediaURLs:mediaURLs];
    MXEventScan *foundEventScan = [self.eventScanStore findWithId:eventId];
    
    XCTAssertNotNil(foundEventScan);
    XCTAssertEqualObjects(insertedEventScan, foundEventScan);
}


- (void)testUpdateEventMediaScans
{
    NSString *eventId = @"123456igzeoijncvoiuhekaj:matrix.org";
    
    NSArray<NSString*>* mediaURLsAtInsertion = @[
                                                 @"mxc://matrix.org/7398H34PHL3904U",
                                                 @"mxc://matrix.org/7398H34PHL3904V"
                                                 ];
    
    NSArray<NSString*>* mediaURLsAtUpdate = @[
                                              @"mxc://matrix.org/7398H34PHL3904V",
                                              @"mxc://matrix.org/7398H34PHL3904W",
                                              @"mxc://matrix.org/7398H34PHL3904X"
                                              ];
    
    MXEventScan *insertedEventScan = [self.eventScanStore createOrUpdateWithId:eventId initialAntivirusStatus:MXAntivirusScanStatusUnknown andMediaURLs:mediaURLsAtInsertion];
    MXEventScan *updatedEventScan = [self.eventScanStore createOrUpdateWithId:eventId initialAntivirusStatus:MXAntivirusScanStatusInProgress andMediaURLs:mediaURLsAtUpdate];
    
    XCTAssertNotNil(insertedEventScan);
    XCTAssertNotNil(updatedEventScan);
    XCTAssertNotEqualObjects(insertedEventScan, updatedEventScan);
    
    XCTAssertEqualObjects(insertedEventScan.eventId, updatedEventScan.eventId);
    XCTAssertEqual(updatedEventScan.antivirusScanStatus, MXAntivirusScanStatusUnknown);
    XCTAssert(updatedEventScan.mediaScans.count == 3);
}

@end

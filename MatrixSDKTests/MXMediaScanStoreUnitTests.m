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
#import "MXRealmMediaScanStore.h"
#import "MXMediaScanStore.h"

@interface MXMediaScanStoreUnitTests : XCTestCase

@property (nonatomic, strong) id<MXScanRealmProvider> realmProvider;
@property (nonatomic, strong) id<MXMediaScanStore> mediaScanStore;

@end

static NSString* const kDefaultAntivirusServerDomain = @"matrix.org";

@implementation MXMediaScanStoreUnitTests

- (void)setUp
{
    [super setUp];

    id<MXScanRealmProvider> realmProvider = [[MXScanRealmInMemoryProvider alloc] initWithAntivirusServerDomain:kDefaultAntivirusServerDomain];
    self.mediaScanStore = [[MXRealmMediaScanStore alloc] initWithRealmProvider:realmProvider];    
    self.realmProvider = realmProvider;
    [self.realmProvider deleteAllObjects];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testCreateMediaScan
{
    NSString *mediaURL = @"mxc://matrix.org/7398H34PHL3904U";
    
    MXMediaScan *mediaScan = [self.mediaScanStore findOrCreateWithURL:mediaURL];
    
    XCTAssertNotNil(mediaScan);
    XCTAssertEqualObjects(mediaScan.url, mediaURL);
    XCTAssertEqual(mediaScan.antivirusScanStatus, MXAntivirusScanStatusUnknown);
    XCTAssertNil(mediaScan.antivirusScanDate);
    XCTAssertNil(mediaScan.antivirusScanInfo);
}

- (void)testCreateSameMediaScanTwice
{
    NSString *mediaURL = @"mxc://matrix.org/7398H34PHL3904U";
    
    MXMediaScan *mediaScan1 = [self.mediaScanStore findOrCreateWithURL:mediaURL];
    MXMediaScan *mediaScan2 = [self.mediaScanStore findOrCreateWithURL:mediaURL];
    
    XCTAssertEqualObjects(mediaScan1, mediaScan2);
}

- (void)testCreateMediaScanWithDefaultValue
{
    NSString *mediaURL = @"mxc://matrix.org/7398H34PHL3904U";
    
    MXAntivirusScanStatus initialAntivirusScanStatus = MXAntivirusScanStatusInProgress;
    
    MXMediaScan *mediaScan = [self.mediaScanStore findOrCreateWithURL:mediaURL initialAntivirusStatus:initialAntivirusScanStatus];
    
    XCTAssertNotNil(mediaScan);
    XCTAssertEqual(mediaScan.antivirusScanStatus, initialAntivirusScanStatus);
}

- (void)testFindMediaScan
{
    NSString *mediaURL = @"mxc://matrix.org/7398H34PHL3904U";
    
    MXMediaScan *insertedMediaScan = [self.mediaScanStore findOrCreateWithURL:mediaURL];
    MXMediaScan *foundMediaScan = [self.mediaScanStore findWithURL:mediaURL];
    
    XCTAssertNotNil(foundMediaScan);
    XCTAssertEqualObjects(insertedMediaScan, foundMediaScan);
}

- (void)testUpdateMediaScan
{
    NSString *mediaURL = @"mxc://matrix.org/7398H34PHL3904U";
    
    MXMediaScan *insertedMediaScan = [self.mediaScanStore findOrCreateWithURL:mediaURL];
    
    XCTAssertNotNil(insertedMediaScan);
    XCTAssertEqual(insertedMediaScan.antivirusScanStatus, MXAntivirusScanStatusUnknown);
    XCTAssertNil(insertedMediaScan.antivirusScanInfo);
    
    MXAntivirusScanStatus updatedAntivirusScanStatus = MXAntivirusScanStatusTrusted;
    NSString *updatedAntivirusScanInfo = @"Clean";
    
    [self.mediaScanStore updateAntivirusScanStatus:updatedAntivirusScanStatus
                                 antivirusScanInfo:updatedAntivirusScanInfo
                                 antivirusScanDate:[NSDate date]
                                            forURL:mediaURL];
    
    MXMediaScan *updatedMediaScan = [self.mediaScanStore findWithURL:mediaURL];
    
    XCTAssertNotNil(updatedMediaScan);
    XCTAssertEqual(updatedMediaScan.antivirusScanStatus, updatedAntivirusScanStatus);
    XCTAssertEqualObjects(updatedMediaScan.antivirusScanInfo, updatedAntivirusScanInfo);
}

@end

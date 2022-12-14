/*
 Copyright 2016 OpenMarket Ltd

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

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface MXAccountDataTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
}
@end

@implementation MXAccountDataTests

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

- (void)testIgnoreUser
{
    [matrixSDKTestsData doMXSessionTestWithBobAndAliceInARoom:self readyToTest:^(MXSession *bobSession, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        XCTAssertEqual(bobSession.ignoredUsers.count, 0);
        XCTAssertEqual([bobSession isUserIgnored:aliceRestClient.credentials.userId], NO);

        // Listen to bobSession.ignoredUsers changes
        [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionIgnoredUsersDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull notif) {

            if (notif.object == bobSession)
            {
                XCTAssertEqual(bobSession.ignoredUsers.count, 1);
                XCTAssertEqual([bobSession isUserIgnored:aliceRestClient.credentials.userId], YES);

                [expectation fulfill];
            }
        }];

        // Ignore Alice
        [bobSession ignoreUsers:@[aliceRestClient.credentials.userId] success:nil failure:^(NSError *error) {
            XCTFail(@"The request should not fail - NSError: %@", error);
            [expectation fulfill];
        }];

    }];
}

// Make sure the ignoredUsers list is still here after resuming a Matrix app
- (void)testIgnoreUsersStorage
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXSession *bobSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:bobSession];

        MXFileStore *store = [[MXFileStore alloc] init];
        [bobSession setStore:store success:^{
            [bobSession start:^{

                // Listen to bobSession.ignoredUsers changes
                [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionIgnoredUsersDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull notif) {

                    if (notif.object == bobSession)
                    {
                        // Yield so that bobSession completes the saving to the cache.
                        // TODO: Find a more accurate point of sync...
                        dispatch_async(dispatch_get_main_queue(), ^{
                            dispatch_async(dispatch_get_main_queue(), ^{

                                [bobSession close];

                                // Check the information have been permanently stored
                                MXSession *bobSession2 = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                                [matrixSDKTestsData retain:bobSession2];
                                MXFileStore *store2 = [[MXFileStore alloc] init];
                                [bobSession2 setStore:store2 success:^{

                                    XCTAssertEqual(bobSession2.ignoredUsers.count, 1);
                                    XCTAssertEqual([bobSession2 isUserIgnored:aliceRestClient.credentials.userId], YES);

                                    [expectation fulfill];

                                } failure:^(NSError *error) {
                                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                    [expectation fulfill];
                                }];
                            });
                        });
                    }

                }];

                // Ignore Alice
                [bobSession ignoreUsers:@[aliceRestClient.credentials.userId] success:nil failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
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

// Make sure an update of ignoredUsers does not kill pushRules
// The reason to test it is that in case of ignoredUsers update, the HS sends only part of
// the account data concerning ignoredUsers
- (void)testIgnoreUserUpdateHasNoCollateralDamageOnPushRules
{
    [matrixSDKTestsData doMXRestClientTestWithBobAndAliceInARoom:self readyToTest:^(MXRestClient *bobRestClient, MXRestClient *aliceRestClient, NSString *roomId, XCTestExpectation *expectation) {

        MXSession *bobSession = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
        [matrixSDKTestsData retain:bobSession];

        MXFileStore *store = [[MXFileStore alloc] init];
        [bobSession setStore:store success:^{
            [bobSession start:^{

                MXPushRulesResponse *pushRules = bobSession.notificationCenter.rules;

                // Listen to bobSession.ignoredUsers changes
                [[NSNotificationCenter defaultCenter] addObserverForName:kMXSessionIgnoredUsersDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull notif) {

                    if (notif.object == bobSession)
                    {
                        // Yield so that bobSession completes the saving to the cache.
                        // TODO: Find a more accurate point of sync...
                        dispatch_async(dispatch_get_main_queue(), ^{
                            dispatch_async(dispatch_get_main_queue(), ^{

                                [bobSession close];

                                // Check the information have been permanently stored
                                MXSession *bobSession2 = [[MXSession alloc] initWithMatrixRestClient:bobRestClient];
                                [matrixSDKTestsData retain:bobSession2];
                                MXFileStore *store2 = [[MXFileStore alloc] init];
                                [bobSession2 setStore:store2 success:^{

                                    MXPushRulesResponse *pushRules2 = bobSession2.notificationCenter.rules;

                                    XCTAssert([pushRules.JSONDictionary isEqualToDictionary:pushRules2.JSONDictionary], @"Push Rules has unexpectedly changed: \n%@\nto:\n%@", pushRules.JSONDictionary, pushRules2.JSONDictionary);

                                    [expectation fulfill];

                                } failure:^(NSError *error) {
                                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                                    [expectation fulfill];
                                }];
                            });
                        });
                    }
                }];

                // Ignore Alice
                [bobSession ignoreUsers:@[aliceRestClient.credentials.userId] success:nil failure:^(NSError *error) {
                    XCTFail(@"The request should not fail - NSError: %@", error);
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


// Test the capability to read or write `m.local_notification_settings.<device-id>`
// events in account data.
- (void)testReadWriteLocalNotificationSettings
{
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {
        XCTAssertNotNil(mxSession.accountData, @"account data shouldn't be nil.");
        XCTAssertNil([mxSession.accountData localNotificationSettingsForDeviceWithId:mxSession.myDeviceId], @"account local notification settings should be nil.");
        
        NSDictionary *localNotificationSettings = @{
            kMXAccountDataIsSilencedKey: @(YES)
        };
        
        [mxSession setAccountData:localNotificationSettings forType:[MXAccountData localNotificationSettingsKeyForDeviceWithId:mxSession.myDeviceId] success:^{
            NSDictionary *localNotificationSettings = [mxSession.accountData localNotificationSettingsForDeviceWithId:mxSession.myDeviceId];
            XCTAssertNotNil(localNotificationSettings, @"account local notification settings shouldn't be nil.");
            NSNumber *isSilenced = localNotificationSettings[kMXAccountDataIsSilencedKey];
            XCTAssertNotNil(isSilenced, @"account local notification is_silenced settings shouldn't be nil.");
            XCTAssertTrue(isSilenced.boolValue, @"is_silenced settings should be set to true.");
            
            localNotificationSettings = @{
                kMXAccountDataIsSilencedKey: @(NO)
            };
            
            [mxSession setAccountData:localNotificationSettings forType:[MXAccountData localNotificationSettingsKeyForDeviceWithId:mxSession.myDeviceId] success:^{
                NSDictionary *localNotificationSettings = [mxSession.accountData localNotificationSettingsForDeviceWithId:mxSession.myDeviceId];
                XCTAssertNotNil(localNotificationSettings, @"account local notification settings shouldn't be nil.");
                NSNumber *isSilenced = localNotificationSettings[kMXAccountDataIsSilencedKey];
                XCTAssertNotNil(isSilenced, @"account local notification is_silenced settings shouldn't be nil.");
                XCTAssertFalse(isSilenced.boolValue, @"is_silenced settings should be set to false.");
                [expectation fulfill];
            } failure:^(NSError *error) {
                XCTFail(@"MXSession setAccountData failed due to error %@", error);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail(@"MXSession setAccountData failed due to error %@", error);
            [expectation fulfill];
        }];
    }];
}

- (void)testEmptyAccountDataEventsAreDeleted
{
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {
        [mxSession setAccountData:@{} forType:@"test" success:^{
            XCTAssertEqual(mxSession.accountData.allAccountDataEvents.count, 2);
            
            [NSNotificationCenter.defaultCenter addObserverForName:kMXSessionAccountDataDidChangeNotification
                                                            object:mxSession
                                                             queue:nil
                                                        usingBlock:^(NSNotification * _Nonnull note) {
                // after the sync the empty account data has been removed
                XCTAssertEqual(mxSession.accountData.allAccountDataEvents.count, 1);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail();
        }];
    }];
}

- (void)testOtherAccountDataEventsArentDeleted
{
    [matrixSDKTestsData doMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {
        [mxSession setAccountData:@{@"key": @"value"} forType:@"test" success:^{
            XCTAssertEqual(mxSession.accountData.allAccountDataEvents.count, 2);
            
            [NSNotificationCenter.defaultCenter addObserverForName:kMXSessionAccountDataDidChangeNotification
                                                            object:mxSession
                                                             queue:nil
                                                        usingBlock:^(NSNotification * _Nonnull note) {
                // after the sync the new account data is there
                XCTAssertEqual(mxSession.accountData.allAccountDataEvents.count, 2);
                [expectation fulfill];
            }];
        } failure:^(NSError *error) {
            XCTFail();
        }];
    }];
}

- (void)testDeletionOfAccountData {
    NSString* accountDataType = @"foo";
    MXAccountData* data = MXAccountData.new;
    
    [data updateDataWithType:accountDataType data:NSDictionary.new];
    XCTAssertNotNil([data accountDataForEventType:accountDataType]);
    
    [data deleteDataWithType:accountDataType];
    XCTAssertNil([data accountDataForEventType:accountDataType]);
}

@end

#pragma clang diagnostic pop

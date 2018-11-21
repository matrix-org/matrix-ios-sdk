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

@import Foundation;
#import "MXAntivirusScanStatus.h"
#import "MXEventScanStoreDelegate.h"

@class MXEventScan;

/**
 The `MXEventScanStore` protocol defines an interface that must be implemented to manipulate event scans data.
 */
@protocol MXEventScanStore <NSObject>

@property (nonatomic, weak, nullable) id<MXEventScanStoreDelegate> delegate;

- (nullable MXEventScan*)findWithId:(nonnull NSString*)eventId;

- (nonnull MXEventScan*)createOrUpdateWithId:(nonnull NSString*)eventId andMediaURLs:(nonnull NSArray<NSString*>*)mediaURLs;

- (nonnull MXEventScan*)createOrUpdateWithId:(nonnull NSString*)eventId initialAntivirusStatus:(MXAntivirusScanStatus)antivirusScanStatus andMediaURLs:(nonnull NSArray<NSString*>*)mediaURLs;

- (BOOL)updateAntivirusScanStatus:(MXAntivirusScanStatus)antivirusScanStatus forId:(nonnull NSString*)eventId;

- (BOOL)updateAntivirusScanStatusFromMediaScansAntivirusScanStatusesAndAntivirusScanDate:(nonnull NSDate*)antivirusScanDate forId:(nonnull NSString*)eventId;

- (void)resetAllAntivirusScanStatusInProgressToUnknown;

- (void)deleteAll;

@end

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
#import "MXMediaScan.h"
#import "MXMediaScanStoreDelegate.h"

/**
 The `MXMediaScanStore` protocol defines an interface that must be implemented to manipulate media scans data.
 */
@protocol MXMediaScanStore <NSObject>

@property (nonatomic, weak, nullable) id<MXMediaScanStoreDelegate> delegate;

- (nonnull MXMediaScan*)findOrCreateWithURL:(nonnull NSString*)url;

- (nonnull MXMediaScan*)findOrCreateWithURL:(nonnull NSString*)url initialAntivirusStatus:(MXAntivirusScanStatus)antivirusScanStatus;

- (nullable MXMediaScan*)findWithURL:(nonnull NSString*)url;

- (BOOL)updateAntivirusScanStatus:(MXAntivirusScanStatus)antivirusScanStatus forURL:(nonnull NSString*)url;

- (BOOL)updateAntivirusScanStatus:(MXAntivirusScanStatus)antivirusScanStatus
                antivirusScanInfo:(nullable NSString*)antivirusScanInfo
                antivirusScanDate:(nonnull NSDate*)antivirusScanDate
                           forURL:(nonnull NSString*)url;

- (void)resetAllAntivirusScanStatusInProgressToUnknown;

- (void)deleteAll;

@end

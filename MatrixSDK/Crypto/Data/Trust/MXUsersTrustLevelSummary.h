/*
 Copyright 2020 The Matrix.org Foundation C.I.C
 
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

#import <Foundation/Foundation.h>

@class MXUsersTrustLevelSummaryMO;

NS_ASSUME_NONNULL_BEGIN

/**
 A summary of the trust for a group of users and their devices
 */
@interface MXUsersTrustLevelSummary : NSObject <NSCoding>

// The ratio of trusted users
@property (nonatomic, strong, readonly) NSProgress *trustedUsersProgress;

// The ratio of trusted devices for trusted users
@property (nonatomic, strong, readonly) NSProgress *trustedDevicesProgress;

- (instancetype)initWithTrustedUsersProgress:(NSProgress*)trustedUsersProgress andTrustedDevicesProgress:(NSProgress*)trustedDevicesProgress;

#pragma mark - CoreData Model

- (instancetype)initWithManagedObject:(MXUsersTrustLevelSummaryMO *)model;

@end

NS_ASSUME_NONNULL_END

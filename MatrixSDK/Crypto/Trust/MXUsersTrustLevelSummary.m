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

#import "MXUsersTrustLevelSummary.h"
#import "MatrixSDKSwiftHeader.h"

@interface MXUsersTrustLevelSummary()

@property (nonatomic, strong, readwrite) MXTrustSummary *usersTrust;
@property (nonatomic, strong, readwrite) MXTrustSummary *devicesTrust;

@end

@implementation MXUsersTrustLevelSummary

- (instancetype)initWithUsersTrust:(MXTrustSummary *)usersTrust
                      devicesTrust:(MXTrustSummary *)devicesTrust
{
    self = [super init];
    if (self)
    {
        self.usersTrust = usersTrust;
        self.devicesTrust = devicesTrust;
    }
    return self;
}

#pragma mark - CoreData Model

- (instancetype)initWithManagedObject:(MXUsersTrustLevelSummaryMO *)model
{
    if (self = [super init])
    {
        self.usersTrust = [[MXTrustSummary alloc] initWithTrustedCount:model.s_trustedUsersCount
                                                            totalCount:model.s_usersCount];
        
        self.devicesTrust = [[MXTrustSummary alloc] initWithTrustedCount:model.s_trustedDevicesCount
                                                              totalCount:model.s_devicesCount];
    }
    return self;
}

#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [self init];
    if (self)
    {
        NSUInteger usersCount = [aDecoder decodeIntegerForKey:@"usersCount"];
        NSUInteger trustedUsersCount = [aDecoder decodeIntegerForKey:@"trustedUsersCount"];
        self.usersTrust = [[MXTrustSummary alloc] initWithTrustedCount:trustedUsersCount totalCount:usersCount];
        
        NSUInteger devicesCount = [aDecoder decodeIntegerForKey:@"devicesCount"];
        NSUInteger trustedDevicesCount = [aDecoder decodeIntegerForKey:@"trustedDevicesCount"];
        self.devicesTrust = [[MXTrustSummary alloc] initWithTrustedCount:trustedDevicesCount totalCount:devicesCount];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeInteger:self.usersTrust.totalCount forKey:@"usersCount"];
    [aCoder encodeInteger:self.usersTrust.trustedCount forKey:@"trustedUsersCount"];
    [aCoder encodeInteger:self.devicesTrust.totalCount forKey:@"devicesCount"];
    [aCoder encodeInteger:self.devicesTrust.trustedCount forKey:@"trustedDevicesCount"];
}


@end

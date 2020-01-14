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

#import "MXDeviceTrustLevel.h"

@implementation MXDeviceTrustLevel

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _localVerificationStatus = MXDeviceUnknown;
        _isCrossSigningVerified = NO;
        _trustOnFirstUse = NO;
    }
    return self;
}

+ (MXDeviceTrustLevel*)trustLevelWithLocalVerificationStatus:(MXDeviceVerification)localVerificationStatus
                                        crossSigningVerified:(BOOL)crossSigningVerified
{
    MXDeviceTrustLevel *trustLevel = [MXDeviceTrustLevel new];
    trustLevel->_localVerificationStatus = localVerificationStatus;
    trustLevel->_isCrossSigningVerified = crossSigningVerified;

    return trustLevel;
}

- (BOOL)isVerified
{
    return self.isLocallyVerified || _isCrossSigningVerified;
}

- (BOOL)isLocallyVerified
{
    return _isCrossSigningVerified == MXDeviceVerified;
}


- (NSString *)description
{
    return [NSString stringWithFormat:@"MXDeviceTrustLevel: local: %@ - cross-signing: %@ - firstUse: %@",  @(_localVerificationStatus), @(_isCrossSigningVerified), @(_trustOnFirstUse)];
}


#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _localVerificationStatus = [(NSNumber*)[aDecoder decodeObjectForKey:@"localVerificationStatus"] unsignedIntegerValue];
        _isCrossSigningVerified = [aDecoder decodeBoolForKey:@"isCrossSigningVerified"];
        _trustOnFirstUse = [aDecoder decodeBoolForKey:@"trustOnFirstUse"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:@(_localVerificationStatus) forKey:@"localVerificationStatus"];
    [aCoder encodeBool:_isCrossSigningVerified forKey:@"isCrossSigningVerified"];
    [aCoder encodeBool:_trustOnFirstUse forKey:@"trustOnFirstUse"];
}

@end

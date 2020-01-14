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

#import "MXUserTrustLevel.h"

@implementation MXUserTrustLevel

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _isCrossSigningVerified = NO;
    }
    return self;
}

+ (MXUserTrustLevel *)trustLevelWithCrossSigningVerified:(BOOL)crossSigningVerified
{
    MXUserTrustLevel *trustLevel = [MXUserTrustLevel new];
    trustLevel->_isCrossSigningVerified = crossSigningVerified;

    return trustLevel;
}

- (BOOL)isVerified
{
    return _isCrossSigningVerified;
}


#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _isCrossSigningVerified = [aDecoder decodeBoolForKey:@"isCrossSigningVerified"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeBool:_isCrossSigningVerified forKey:@"isCrossSigningVerified"];
}

@end

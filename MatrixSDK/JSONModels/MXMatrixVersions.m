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

#import "MXMatrixVersions.h"

const struct MXMatrixClientServerAPIVersionStruct MXMatrixClientServerAPIVersion = {
    .r0_0_1 = @"r0.0.1",
    .r0_1_0 = @"r0.1.0",
    .r0_2_0 = @"r0.2.0",
    .r0_3_0 = @"r0.3.0",
    .r0_4_0 = @"r0.4.0",
    .r0_5_0 = @"r0.5.0",
    .r0_6_0 = @"r0.6.0",
    .r0_6_1 = @"r0.6.1",
    .v1_1   = @"v1.1",
    .v1_2   = @"v1.2",
    .v1_3   = @"v1.3",
    // missing versions not considered
    .v1_11  = @"v1.11"
};

const struct MXMatrixVersionsFeatureStruct MXMatrixVersionsFeature = {
    .lazyLoadMembers = @"m.lazy_load_members",
    .requireIdentityServer = @"m.require_identity_server",
    .idAccessToken = @"m.id_access_token",
    .separateAddAndBind = @"m.separate_add_and_bind"
};

static NSString* const kJSONKeyVersions = @"versions";
static NSString* const kJSONKeyUnstableFeatures = @"unstable_features";

//  Unstable features
static NSString* const kJSONKeyMSC3440 = @"org.matrix.msc3440.stable";
static NSString* const kJSONKeyMSC3881Unstable = @"org.matrix.msc3881";
static NSString* const kJSONKeyMSC3881 = @"org.matrix.msc3881.stable";
static NSString* const kJSONKeyMSC3882 = @"org.matrix.msc3882";
static NSString* const kJSONKeyMSC3773 = @"org.matrix.msc3773";
static NSString* const kJSONKeyMSC3912Unstable = @"org.matrix.msc3912";
static NSString* const kJSONKeyMSC3912 = @"org.matrix.msc3912.stable";

@interface MXMatrixVersions ()

@property (nonatomic, readwrite) NSArray<NSString *> *versions;
@property (nonatomic, nullable, readwrite) NSDictionary<NSString*, NSNumber*> *unstableFeatures;

@end

@implementation MXMatrixVersions

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    if (JSONDictionary[kJSONKeyVersions])
    {
        MXMatrixVersions *result = [MXMatrixVersions new];

        MXJSONModelSetArray(result.versions, JSONDictionary[kJSONKeyVersions]);
        MXJSONModelSetDictionary(result.unstableFeatures, JSONDictionary[kJSONKeyUnstableFeatures]);

        return result;
    }
    return nil;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];

    JSONDictionary[kJSONKeyVersions] = self.versions;

    if (self.unstableFeatures)
    {
        JSONDictionary[kJSONKeyUnstableFeatures] = self.unstableFeatures;
    }

    return JSONDictionary;
}

- (BOOL)supportLazyLoadMembers
{
    return [self serverSupportsVersion:MXMatrixClientServerAPIVersion.r0_5_0]
    || [self serverSupportsFeature:MXMatrixVersionsFeature.lazyLoadMembers];
}

- (BOOL)doesServerRequireIdentityServerParam
{
    if ([self serverSupportsVersion:MXMatrixClientServerAPIVersion.r0_6_0])
    {
        return NO;
    }

    return [self serverSupportsFeature:MXMatrixVersionsFeature.requireIdentityServer
                          defaultValue:YES];
}

- (BOOL)doesServerAcceptIdentityAccessToken
{
    return [self serverSupportsVersion:MXMatrixClientServerAPIVersion.r0_6_0]
    || [self serverSupportsFeature:MXMatrixVersionsFeature.idAccessToken];
}

- (BOOL)doesServerSupportSeparateAddAndBind
{
    return [self serverSupportsVersion:MXMatrixClientServerAPIVersion.r0_6_0]
    || [self serverSupportsFeature:MXMatrixVersionsFeature.separateAddAndBind];
}

- (BOOL)supportsThreads
{
    // TODO: Check for v1.3 or whichever spec version formally specifies MSC3440.
    return [self serverSupportsFeature:kJSONKeyMSC3440];
}

- (BOOL)supportsRemotelyTogglingPushNotifications
{
    return [self serverSupportsFeature:kJSONKeyMSC3881] || [self serverSupportsFeature:kJSONKeyMSC3881Unstable];
}

- (BOOL)supportsQRLogin
{
    return [self serverSupportsFeature:kJSONKeyMSC3882];
}

- (BOOL)supportsNotificationsForThreads {
    return [self serverSupportsFeature:kJSONKeyMSC3773];
}

- (BOOL)supportsRedactionWithRelations
{
    return [self serverSupportsFeature:kJSONKeyMSC3912];
}

- (BOOL)supportsRedactionWithRelationsUnstable
{
    return [self serverSupportsFeature:kJSONKeyMSC3912Unstable];
}

- (BOOL)supportsAuthenticatedMedia
{
    return [self serverSupportsVersion:MXMatrixClientServerAPIVersion.v1_11];
}

#pragma mark - Private

- (BOOL)serverSupportsVersion:(NSString *)version
{
    //  we might improve this logic in future, so moved into a dedicated method.
    return [self.versions containsObject:version];
}

- (BOOL)serverSupportsFeature:(NSString *)feature
{
    return [self serverSupportsFeature:feature defaultValue:NO];
}

- (BOOL)serverSupportsFeature:(NSString *)feature defaultValue:(BOOL)defaultValue
{
    if (self.unstableFeatures[feature])
    {
        return self.unstableFeatures[feature].boolValue;
    }
    return defaultValue;
}

#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super init])
    {
        self.versions = [aDecoder decodeObjectForKey:kJSONKeyVersions];
        self.unstableFeatures = [aDecoder decodeObjectForKey:kJSONKeyUnstableFeatures];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:self.versions forKey:kJSONKeyVersions];
    [aCoder encodeObject:self.unstableFeatures forKey:kJSONKeyUnstableFeatures];
}

@end

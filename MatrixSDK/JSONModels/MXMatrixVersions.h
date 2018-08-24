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

#import <Foundation/Foundation.h>
#import "MXJSONModel.h"

/**
 Features declared in the matrix specification.
 */
struct MXMatrixVersionsFeatureStruct
{
    // Room members lazy loading
    __unsafe_unretained NSString * const lazyLoadMembers;
};
extern const struct MXMatrixVersionsFeatureStruct MXMatrixVersionsFeature;

/**
 `MXMatrixVersions` represents the versions of the Matrix specification supported
 by the home server.
 It is returned by the /versions API.
 */
@interface MXMatrixVersions : MXJSONModel

/**
 The versions supported by the server.
 */
@property (nonatomic) NSArray<NSString *> *versions;

/**
 The unstable features supported by the server.

 */
@property (nonatomic) NSDictionary<NSString*, NSNumber*> *unstableFeatures;

/**
 Check whether the server supports the room members lazy loading.
 */
@property (nonatomic, readonly) BOOL supportLazyLoadMembers;

@end

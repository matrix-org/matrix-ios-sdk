// 
// Copyright 2020 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <Foundation/Foundation.h>
#import "MXJSONModel.h"

typedef NSString * MXCallSessionDescriptionTypeString;
FOUNDATION_EXPORT NSString *const kMXCallSessionDescriptionTypeStringOffer;
FOUNDATION_EXPORT NSString *const kMXCallSessionDescriptionTypeStringPrAnswer;
FOUNDATION_EXPORT NSString *const kMXCallSessionDescriptionTypeStringAnswer;
FOUNDATION_EXPORT NSString *const kMXCallSessionDescriptionTypeStringRollback;

/**
 MXCallSessionDescription types
 */
typedef enum : NSUInteger
{
    MXCallSessionDescriptionTypeOffer,
    MXCallSessionDescriptionTypePrAnswer,
    MXCallSessionDescriptionTypeAnswer,
    MXCallSessionDescriptionTypeRollback
} MXCallSessionDescriptionType NS_REFINED_FOR_SWIFT;

/**
 `MXCallOffer` represents a call session description.
 */
@interface MXCallSessionDescription : MXJSONModel

/**
 The type of session description (as string).
 */
@property (nonatomic) MXCallSessionDescriptionTypeString typeString;

/**
 The SDP text of the session description.
 */
@property (nonatomic) NSString *sdp;

/**
 The mapped enum type of session description.
 */
@property (nonatomic) MXCallSessionDescriptionType type;

@end

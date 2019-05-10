/*
 Copyright 2019 New Vector Ltd

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

NS_ASSUME_NONNULL_BEGIN


#pragma mark - Constants

/**
 Annotation relation like reactions.
 */
FOUNDATION_EXPORT NSString * _Nonnull const MXEventContentRelatesToAnnotationType;

/**
 Reply relation.
 */

FOUNDATION_EXPORT NSString * _Nonnull const MXEventContentRelatesToReferenceType;

/**
 Edition relation.
 */
FOUNDATION_EXPORT NSString * _Nonnull const MXEventContentRelatesToReplaceType;


/**
 JSON model for MXEvent.content.relates_to.
 */
@interface MXEventContentRelatesTo : MXJSONModel

@property (nonatomic, readonly) NSString *relationType;
@property (nonatomic, readonly) NSString *eventId;
@property (nonatomic, readonly, nullable) NSString *key;

@end

NS_ASSUME_NONNULL_END

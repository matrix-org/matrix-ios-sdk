// 
// Copyright 2021 The Matrix.org Foundation C.I.C
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

NS_ASSUME_NONNULL_BEGIN

/**
 JSON model for the response from /_matrix/media/r0/preview_url
 */
@interface MXURLPreview : MXJSONModel

/**
 The OpenGraph site name for the URL.
 */
@property (nonatomic, readonly, nullable) NSString *siteName;

/**
 The OpenGraph title for the URL.
 */
@property (nonatomic, readonly, nullable) NSString *title;

/**
 The OpenGraph description for the URL.
 */
@property (nonatomic, readonly, nullable) NSString *text;

/**
 The OpenGraph image's URL.
 */
@property (nonatomic, readonly, nullable) NSString *imageURL;

/**
 The OpenGraph image's type.
 */
@property (nonatomic, readonly, nullable) NSString *imageType;

/**
 The OpenGraph image's width.
 */
@property (nonatomic, readonly, nullable) NSNumber *imageWidth;

/**
 The OpenGraph image's height.
 */
@property (nonatomic, readonly, nullable) NSNumber *imageHeight;

/**
 The byte-size of the image at `imageURL`.
 */
@property (nonatomic, readonly, nullable) NSNumber *imageFileSize;

@end

NS_ASSUME_NONNULL_END

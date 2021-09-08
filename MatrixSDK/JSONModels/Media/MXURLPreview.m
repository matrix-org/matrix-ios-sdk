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

#import "MXURLPreview.h"

@implementation MXURLPreview

static NSString * const kSiteNameJSONKey = @"og:site_name";
static NSString * const kTitleJSONKey = @"og:title";
static NSString * const kDescriptionJSONKey = @"og:description";
static NSString * const kImageURLJSONKey = @"og:image";
static NSString * const kImageTypeJSONKey = @"og:image:type";
static NSString * const kImageWidthJSONKey = @"og:image:width";
static NSString * const kImageHeightJSONKey = @"og:image:height";
static NSString * const kImageFileSizeJSONKey = @"matrix:image:size";

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXURLPreview *urlPreview = [MXURLPreview new];
    
    NSString *siteName, *title, *description, *imageURL, *imageType;
    NSNumber *imageWidth, *imageHeight, *imageFileSize;
    
    MXJSONModelSetString(siteName, JSONDictionary[kSiteNameJSONKey]);
    MXJSONModelSetString(title, JSONDictionary[kTitleJSONKey]);
    MXJSONModelSetString(description, JSONDictionary[kDescriptionJSONKey]);
    MXJSONModelSetString(imageURL, JSONDictionary[kImageURLJSONKey]);
    MXJSONModelSetString(imageType, JSONDictionary[kImageTypeJSONKey]);
    MXJSONModelSetNumber(imageWidth, JSONDictionary[kImageWidthJSONKey]);
    MXJSONModelSetNumber(imageHeight, JSONDictionary[kImageHeightJSONKey]);
    MXJSONModelSetNumber(imageFileSize, JSONDictionary[kImageFileSizeJSONKey]);
    
    urlPreview->_siteName = siteName;
    urlPreview->_title = title;
    urlPreview->_text = description;
    urlPreview->_imageURL = imageURL;
    urlPreview->_imageType = imageType;
    urlPreview->_imageWidth = imageWidth;
    urlPreview->_imageHeight = imageHeight;
    urlPreview->_imageFileSize = imageFileSize;
    
    return urlPreview;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    if (JSONDictionary)
    {
        if (self.siteName)
        {
            JSONDictionary[kSiteNameJSONKey] = self.siteName;
        }
        if (self.title)
        {
            JSONDictionary[kTitleJSONKey] = self.title;
        }
        if (self.text)
        {
            JSONDictionary[kDescriptionJSONKey] = self.text;
        }
        if (self.imageURL)
        {
            JSONDictionary[kImageURLJSONKey] = self.imageURL;
        }
        if (self.imageType)
        {
            JSONDictionary[kImageTypeJSONKey] = self.imageType;
        }
        if (self.imageWidth)
        {
            JSONDictionary[kImageWidthJSONKey] = self.imageWidth;
        }
        if (self.imageHeight)
        {
            JSONDictionary[kImageHeightJSONKey] = self.imageHeight;
        }
        if (self.imageFileSize)
        {
            JSONDictionary[kImageFileSizeJSONKey] = self.imageFileSize;
        }
    }
    
    return JSONDictionary;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self) {
        _siteName = [coder decodeObjectForKey:kSiteNameJSONKey];
        _title = [coder decodeObjectForKey:kTitleJSONKey];
        _text = [coder decodeObjectForKey:kDescriptionJSONKey];
        _imageURL = [coder decodeObjectForKey:kImageURLJSONKey];
        _imageType = [coder decodeObjectForKey:kImageTypeJSONKey];
        _imageWidth = [coder decodeObjectForKey:kImageWidthJSONKey];
        _imageHeight = [coder decodeObjectForKey:kImageHeightJSONKey];
        _imageFileSize = [coder decodeObjectForKey:kImageFileSizeJSONKey];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_siteName forKey:kSiteNameJSONKey];
    [coder encodeObject:_title forKey:kTitleJSONKey];
    [coder encodeObject:_text forKey:kDescriptionJSONKey];
    [coder encodeObject:_imageURL forKey:kImageURLJSONKey];
    [coder encodeObject:_imageType forKey:kImageTypeJSONKey];
    [coder encodeObject:_imageWidth forKey:kImageWidthJSONKey];
    [coder encodeObject:_imageHeight forKey:kImageHeightJSONKey];
    [coder encodeObject:_imageFileSize forKey:kImageFileSizeJSONKey];
}

@end

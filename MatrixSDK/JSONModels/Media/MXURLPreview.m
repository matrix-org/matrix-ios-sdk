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

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXURLPreview *urlPreview = [MXURLPreview new];
    
    NSString *title, *description, *imageURL, *imageType;
    NSNumber *imageWidth, *imageHeight, *imageFileSize;
    
    MXJSONModelSetString(title, JSONDictionary[@"og:title"]);
    MXJSONModelSetString(description, JSONDictionary[@"og:description"]);
    MXJSONModelSetString(imageURL, JSONDictionary[@"og:image"]);
    MXJSONModelSetString(imageType, JSONDictionary[@"og:image:type"]);
    
    MXJSONModelSetNumber(imageWidth, JSONDictionary[@"og:image:width"]);
    MXJSONModelSetNumber(imageHeight, JSONDictionary[@"og:image:height"]);
    MXJSONModelSetNumber(imageFileSize, JSONDictionary[@"matrix:image:size"]);
    
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
        if (self.title)
        {
            JSONDictionary[@"og:title"] = self.title;
        }
        if (self.text)
        {
            JSONDictionary[@"og:description"] = self.text;
        }
        if (self.imageURL)
        {
            JSONDictionary[@"og:image"] = self.imageURL;
        }
        if (self.imageType)
        {
            JSONDictionary[@"og:image:type"] = self.imageType;
        }
        if (self.imageWidth)
        {
            JSONDictionary[@"og:image:width"] = self.imageWidth;
        }
        if (self.imageHeight)
        {
            JSONDictionary[@"og:image:height"] = self.imageHeight;
        }
        if (self.imageFileSize)
        {
            JSONDictionary[@"matrix:image:size"] = self.imageFileSize;
        }
    }
    
    return JSONDictionary;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self) {
        _title = [coder decodeObjectForKey:@"og:title"];
        _text = [coder decodeObjectForKey:@"og:description"];
        _imageURL = [coder decodeObjectForKey:@"og:image"];
        _imageType = [coder decodeObjectForKey:@"og:image:type"];
        _imageWidth = [coder decodeObjectForKey:@"og:image:width"];
        _imageHeight = [coder decodeObjectForKey:@"og:image:height"];
        _imageFileSize = [coder decodeObjectForKey:@"matrix:image:size"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_title forKey:@"og:title"];
    [coder encodeObject:_text forKey:@"og:description"];
    [coder encodeObject:_imageURL forKey:@"og:image"];
    [coder encodeObject:_imageType forKey:@"og:image:type"];
    [coder encodeObject:_imageWidth forKey:@"og:image:width"];
    [coder encodeObject:_imageHeight forKey:@"og:image:height"];
    [coder encodeObject:_imageFileSize forKey:@"matrix:image:size"];
}

@end

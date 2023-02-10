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

#import "MXSendReplyEventDefaultStringLocalizer.h"

@interface MXSendReplyEventDefaultStringLocalizer ()

@property (nonatomic, strong) NSString *senderSentAnImage;
@property (nonatomic, strong) NSString *senderSentAVideo;
@property (nonatomic, strong) NSString *senderSentAnAudioFile;
@property (nonatomic, strong) NSString *senderSentAVoiceMessage;
@property (nonatomic, strong) NSString *senderSentAFile;
@property (nonatomic, strong) NSString *senderSentTheirLocation;
@property (nonatomic, strong) NSString *senderSentTheirLiveLocation;
@property (nonatomic, strong) NSString *messageToReplyToPrefix;
@property (nonatomic, strong) NSString *endedPollMessage;

@end

@implementation MXSendReplyEventDefaultStringLocalizer

- (instancetype)init
{
    self = [super init];
    if (self) {
        _senderSentAnImage = @"sent an image.";
        _senderSentAVideo = @"sent a video.";
        _senderSentAnAudioFile = @"sent an audio file.";
        _senderSentAVoiceMessage = @"sent a voice message.";
        _senderSentAFile = @"sent a file.";
        _senderSentTheirLocation = @"has shared their location.";
        _senderSentTheirLiveLocation = @"Live location.";
        _messageToReplyToPrefix = @"In reply to";
        _endedPollMessage = @"Ended poll";
    }
    return self;
}

@end

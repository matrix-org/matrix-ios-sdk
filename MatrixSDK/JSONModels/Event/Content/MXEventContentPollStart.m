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

#import "MXEventContentPollStart.h"
#import "MXEvent.h"

@implementation MXEventContentPollStart

- (instancetype)initWithQuestion:(NSString *)question
                            kind:(NSString *)kind
                   maxSelections:(NSNumber *)maxSelections
                   answerOptions:(NSArray<MXEventContentPollStartAnswerOption *> *)answerOptions
{
    if (self = [super init]) {
        _question = question;
        _kind = kind;
        _maxSelections = maxSelections;
        _answerOptions = answerOptions;
    }
    
    return self;
}

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    NSDictionary *content = JSONDictionary[kMXMessageContentKeyExtensiblePollStartMSC3381];
    if (content == nil) {
        content = JSONDictionary[kMXMessageContentKeyExtensiblePollStart];
    }
    
    if (content == nil) {
        return nil;
    }
    
    NSString *question = content[kMXMessageContentKeyExtensiblePollQuestion][kMXMessageContentKeyExtensibleTextMSC1767];
    if (question == nil) {
        question = content[kMXMessageContentKeyExtensiblePollQuestion][kMXMessageContentKeyExtensibleText];
    }
    
    if (question.length == 0) {
        return nil;
    }
    
    NSString *kind;
    MXJSONModelSetString(kind, content[kMXMessageContentKeyExtensiblePollKind]);
    
    NSNumber *maxSelections;
    MXJSONModelSetNumber(maxSelections, content[kMXMessageContentKeyExtensiblePollMaxSelections]);
    
    NSArray<MXEventContentPollStartAnswerOption *> *answerOptions = [MXEventContentPollStartAnswerOption modelsFromJSON:content[kMXMessageContentKeyExtensiblePollAnswers]];
    
    return [[MXEventContentPollStart alloc] initWithQuestion:question
                                                        kind:kind
                                               maxSelections:maxSelections
                                               answerOptions:answerOptions];
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    
    content[kMXMessageContentKeyExtensiblePollQuestion] = @{kMXMessageContentKeyExtensibleTextMSC1767: self.question};
    content[kMXMessageContentKeyExtensiblePollKind] = self.kind;
    content[kMXMessageContentKeyExtensiblePollMaxSelections] = self.maxSelections;
    
    NSMutableArray *answerOptions = [NSMutableArray arrayWithCapacity:self.answerOptions.count];
    for (MXEventContentPollStartAnswerOption *answerOption in self.answerOptions)
    {
        [answerOptions addObject:answerOption.JSONDictionary];
    }
    
    content[kMXMessageContentKeyExtensiblePollAnswers] = answerOptions;
    
    return @{kMXMessageContentKeyExtensiblePollStartMSC3381: content};
}

@end


@implementation MXEventContentPollStartAnswerOption

- (instancetype)initWithUUID:(NSString *)uuid text:(NSString *)text
{
    if (self = [super init])
    {
        _uuid = uuid;
        _text = text;
    }
    
    return self;
}

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    NSString *uuid;
    MXJSONModelSetString(uuid, JSONDictionary[kMXMessageContentKeyExtensiblePollAnswerId]);
    
    NSString *text = JSONDictionary[kMXMessageContentKeyExtensibleTextMSC1767];
    if (text == nil) {
        text = JSONDictionary[kMXMessageContentKeyExtensibleText];
    }
    
    if (text.length == 0) {
        return nil;
    }

    return [[MXEventContentPollStartAnswerOption alloc] initWithUUID:uuid text:text];
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    
    JSONDictionary[kMXMessageContentKeyExtensiblePollAnswerId] = self.uuid;
    JSONDictionary[kMXMessageContentKeyExtensibleTextMSC1767] = self.text;
    
    return JSONDictionary;
}

@end

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

#import "MXEventRelations.h"

#import "MXEventAnnotationChunk.h"
#import "MXEventReferenceChunk.h"
#import "MXEventReplace.h"
#import "MXEventRelationThread.h"
#import "MXEvent.h"

@implementation MXEventRelations

#pragma mark - MXJSONModel

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXEventRelations *relations;

    MXEventAnnotationChunk *annotation;
    MXJSONModelSetMXJSONModel(annotation, MXEventAnnotationChunk, JSONDictionary[MXEventRelationTypeAnnotation]);

    MXEventReferenceChunk *reference;
    MXJSONModelSetMXJSONModel(reference, MXEventReferenceChunk, JSONDictionary[MXEventRelationTypeReference]);

    MXEventReplace *eventReplace;
    MXJSONModelSetMXJSONModel(eventReplace, MXEventReplace, JSONDictionary[MXEventRelationTypeReplace]);

    MXEventRelationThread *thread;
    MXJSONModelSetMXJSONModel(thread, MXEventRelationThread, JSONDictionary[MXEventRelationTypeThread]);

    if (annotation || reference || eventReplace || thread)
    {
        relations = [MXEventRelations new];
        relations->_annotation = annotation;
        relations->_reference = reference;
        relations->_replace = eventReplace;
        relations->_thread = thread;
    }

    return relations;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    if (JSONDictionary)
    {
        if (_annotation)
        {
            JSONDictionary[MXEventRelationTypeAnnotation] = _annotation.JSONDictionary;
        }

        if (_reference)
        {
            JSONDictionary[MXEventRelationTypeReference] = _reference.JSONDictionary;
        }

        if (_replace)
        {
            JSONDictionary[MXEventRelationTypeReplace] = _replace.JSONDictionary;
        }

        if (_thread)
        {
            JSONDictionary[MXEventRelationTypeThread] = _thread.JSONDictionary;
        }
    }

    return JSONDictionary;
}


#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _annotation = [aDecoder decodeObjectForKey:@"annotation"];
        _reference = [aDecoder decodeObjectForKey:@"reference"];
        _replace = [aDecoder decodeObjectForKey:@"replace"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_annotation forKey:@"annotation"];
    [aCoder encodeObject:_reference forKey:@"reference"];
    [aCoder encodeObject:_replace forKey:@"replace"];
}

@end

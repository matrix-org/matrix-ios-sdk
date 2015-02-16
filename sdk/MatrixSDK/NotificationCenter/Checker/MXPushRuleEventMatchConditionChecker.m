/*
 Copyright 2015 OpenMarket Ltd

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

#import "MXPushRuleEventMatchConditionChecker.h"

@implementation MXPushRuleEventMatchConditionChecker

- (BOOL)isCondition:(MXPushRuleCondition*)condition satisfiedBy:(MXEvent*)event
{
    BOOL isSatisfied = NO;

    // Come back to JSON dictionary in order to easily travel to key path defined by condition.parameter.key
    NSDictionary *JSONDictionary = event.originalDictionary;

    // Retrieve the value
    NSObject *value = [JSONDictionary valueForKeyPath:condition.parameters[@"key"]];
    if (value && [value isKindOfClass:[NSString class]])
    {
        // If it exists, compare it to the regular expression in condition.parameter.pattern
        NSString *stringValue = (NSString *)value;

        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:[self globToRegex:(NSString*)condition.parameters[@"pattern"] ]
                                                                               options:0 error:nil];

        if ([regex numberOfMatchesInString:stringValue options:0 range:NSMakeRange(0, stringValue.length)])
        {
            isSatisfied = YES;
        }
    }

    return isSatisfied;
}

- (NSString*)globToRegex:(NSString*)glob
{
    NSString *res = [glob stringByReplacingOccurrencesOfString:@"*" withString:@".*"];
    res = [res stringByReplacingOccurrencesOfString:@"?" withString:@"."];

    if ([res isEqualToString:glob])
    {
        // If no special characters were found (detected here by no replacements having been made),
        // add asterisks to both sides
        res = [NSString stringWithFormat:@".*%@.*", glob];
    }

    return res;
}

@end

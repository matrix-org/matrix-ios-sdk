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

#import "MXSASTransaction.h"

#import "MXKey.h"


#pragma mark - Constants

NSString * const MXKeyVerificationMethodSAS        = @"m.sas.v1";
NSString * const MXKeyVerificationSASModeDecimal   = @"decimal";
NSString * const MXKeyVerificationSASModeEmoji     = @"emoji";

NSString * const MXKeyVerificationSASMacSha256         = @"hkdf-hmac-sha256";
NSString * const MXKeyVerificationSASMacSha256LongKdf  = @"hmac-sha256";

NSArray<NSString*> *kKnownAgreementProtocols;
NSArray<NSString*> *kKnownHashes;
NSArray<NSString*> *kKnownMacs;
NSArray<NSString*> *kKnownShortCodes;

static NSArray<MXEmojiRepresentation*> *kSasEmojis;


@implementation MXLegacySASTransaction

#pragma mark - Emoji representation
+ (void)initializeSasEmojis
{
    if (!kSasEmojis)
    {
        kSasEmojis = @[
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🐶" andName:@"dog"],        //  0
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🐱" andName:@"cat"],        //  1
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🦁" andName:@"lion"],       //  2
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🐎" andName:@"horse"],      //  3
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🦄" andName:@"unicorn"],    //  4
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🐷" andName:@"pig"],        //  5
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🐘" andName:@"elephant"],   //  6
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🐰" andName:@"rabbit"],     //  7
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🐼" andName:@"panda"],      //  8
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🐓" andName:@"rooster"],    //  9
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🐧" andName:@"penguin"],    // 10
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🐢" andName:@"turtle"],     // 11
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🐟" andName:@"fish"],       // 12
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🐙" andName:@"octopus"],    // 13
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🦋" andName:@"butterfly"],  // 14
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🌷" andName:@"flower"],     // 15
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🌳" andName:@"tree"],       // 16
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🌵" andName:@"cactus"],     // 17
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🍄" andName:@"mushroom"],   // 18
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🌏" andName:@"globe"],      // 19
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🌙" andName:@"moon"],       // 20
            [[MXEmojiRepresentation alloc] initWithEmoji:@"☁️" andName:@"cloud"],      // 21
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🔥" andName:@"fire"],       // 22
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🍌" andName:@"banana"],     // 23
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🍎" andName:@"apple"],      // 24
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🍓" andName:@"strawberry"], // 25
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🌽" andName:@"corn"],       // 26
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🍕" andName:@"pizza"],      // 27
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🎂" andName:@"cake"],       // 28
            [[MXEmojiRepresentation alloc] initWithEmoji:@"❤️" andName:@"heart"],      // 29
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🙂" andName:@"smiley"],     // 30
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🤖" andName:@"robot"],      // 31
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🎩" andName:@"hat"],        // 32
            [[MXEmojiRepresentation alloc] initWithEmoji:@"👓" andName:@"glasses"],    // 33
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🔧" andName:@"spanner"],    // 34
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🎅" andName:@"santa"],      // 35
            [[MXEmojiRepresentation alloc] initWithEmoji:@"👍" andName:@"thumbs up"],  // 36
            [[MXEmojiRepresentation alloc] initWithEmoji:@"☂️" andName:@"umbrella"],   // 37
            [[MXEmojiRepresentation alloc] initWithEmoji:@"⌛" andName:@"hourglass"],  // 38
            [[MXEmojiRepresentation alloc] initWithEmoji:@"⏰" andName:@"clock"],      // 39
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🎁" andName:@"gift"],       // 40
            [[MXEmojiRepresentation alloc] initWithEmoji:@"💡" andName:@"light bulb"], // 41
            [[MXEmojiRepresentation alloc] initWithEmoji:@"📕" andName:@"book"],       // 42
            [[MXEmojiRepresentation alloc] initWithEmoji:@"✏️" andName:@"pencil"],     // 43
            [[MXEmojiRepresentation alloc] initWithEmoji:@"📎" andName:@"paperclip"],  // 44
            [[MXEmojiRepresentation alloc] initWithEmoji:@"✂️" andName:@"scissors"],   // 45
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🔒" andName:@"lock"],       // 46
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🔑" andName:@"key"],        // 47
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🔨" andName:@"hammer"],     // 48
            [[MXEmojiRepresentation alloc] initWithEmoji:@"☎️" andName:@"telephone"],  // 49
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🏁" andName:@"flag"],       // 50
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🚂" andName:@"train"],      // 51
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🚲" andName:@"bicycle"],    // 52
            [[MXEmojiRepresentation alloc] initWithEmoji:@"✈️" andName:@"aeroplane"],  // 53
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🚀" andName:@"rocket"],     // 54
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🏆" andName:@"trophy"],     // 55
            [[MXEmojiRepresentation alloc] initWithEmoji:@"⚽" andName:@"ball"],       // 56
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🎸" andName:@"guitar"],     // 57
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🎺" andName:@"trumpet"],    // 58
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🔔" andName:@"bell"],       // 59
            [[MXEmojiRepresentation alloc] initWithEmoji:@"⚓️" andName:@"anchor"],     // 60
            [[MXEmojiRepresentation alloc] initWithEmoji:@"🎧" andName:@"headphones"], // 61
            [[MXEmojiRepresentation alloc] initWithEmoji:@"📁" andName:@"folder"],     // 62
            [[MXEmojiRepresentation alloc] initWithEmoji:@"📌" andName:@"pin"],        // 63
        ];
    }
}

+ (NSArray<MXEmojiRepresentation*> *)allEmojiRepresentations
{
    [MXLegacySASTransaction initializeSasEmojis];
    return kSasEmojis;
}

@end

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

#import "MXRoomLastMessage.h"
#import "MXEvent.h"
#import "MXKeyProvider.h"
#import "MXAesKeyData.h"
#import "MXAes.h"
#import "MatrixSDKSwiftHeader.h"

#import <Security/Security.h>
#import <CommonCrypto/CommonCryptor.h>

NSString *const MXRoomLastMessageDataType = @"org.matrix.sdk.keychain.MXRoomLastMessage";

NSString *const kCodingKeyEventId = @"eventId";
NSString *const kCodingKeyOriginServerTs = @"originServerTs";
NSString *const kCodingKeyIsEncrypted = @"isEncrypted";
NSString *const kCodingKeySender = @"sender";
NSString *const kCodingKeyData = @"data";
NSString *const kCodingKeyEncryptedData = @"encryptedData";
NSString *const kCodingKeyText = @"text";
NSString *const kCodingKeyAttributedText = @"attributedText";
NSString *const kCodingKeyOthers = @"others";

@interface MXRoomLastMessage ()

@property (nonatomic, copy, readwrite) NSString *eventId;

@property (nonatomic, assign, readwrite) uint64_t originServerTs;

@end

@implementation MXRoomLastMessage

- (instancetype)initWithEvent:(MXEvent *)event
{
    if (self = [super init])
    {
        _eventId = event.eventId;
        _originServerTs = event.originServerTs;
        _isEncrypted = event.isEncrypted;
        _sender = event.sender;
    }
    return self;
}

- (NSComparisonResult)compareOriginServerTs:(MXRoomLastMessage *)otherMessage
{
    NSComparisonResult result = NSOrderedAscending;
    if (otherMessage.originServerTs > _originServerTs)
    {
        result = NSOrderedDescending;
    }
    else if (otherMessage.originServerTs == _originServerTs)
    {
        result = NSOrderedSame;
    }
    return result;
}

- (NSString*)description
{
    return [NSString stringWithFormat:@"%@: %@ - %llu", super.description, self.eventId, self.originServerTs];
}

#pragma mark - CoreData Model

- (instancetype)initWithCoreDataModel:(MXRoomLastMessageModel *)model
{
    if (self = [super init])
    {
        _eventId = model.s_eventId;
        _originServerTs = model.s_originServerTs;
        _isEncrypted = model.s_isEncrypted;
        _sender = model.s_sender;
        _text = model.s_text;
        if (model.s_attributedText)
        {
            _attributedText = [NSKeyedUnarchiver unarchiveObjectWithData:model.s_attributedText];
        }
        if (model.s_others)
        {
            _others = [NSKeyedUnarchiver unarchiveObjectWithData:model.s_others];
        }
    }
    return self;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super init])
    {
        _eventId = [coder decodeObjectForKey:kCodingKeyEventId];
        _originServerTs = [coder decodeInt64ForKey:kCodingKeyOriginServerTs];
        _isEncrypted = [coder decodeBoolForKey:kCodingKeyIsEncrypted];
        _sender = [coder decodeObjectForKey:kCodingKeySender];

        NSDictionary *lastMessageDictionary;
        if (_isEncrypted)
        {
            NSData *lastMessageEncryptedData = [coder decodeObjectForKey:kCodingKeyEncryptedData];
            NSData *lastMessageData = [self decrypt:lastMessageEncryptedData];
            
            //  Sanity check. If `decrypt` fails, returns nil and causes NSKeyedUnarchiver raise an exception.
            if (lastMessageData)
            {
                lastMessageDictionary = [NSKeyedUnarchiver unarchiveObjectWithData:lastMessageData];
            }
        }
        else
        {
            lastMessageDictionary = [coder decodeObjectForKey:kCodingKeyData];
        }
        _text = lastMessageDictionary[kCodingKeyText];
        _attributedText = lastMessageDictionary[kCodingKeyAttributedText];
        _others = [lastMessageDictionary[kCodingKeyOthers] mutableCopy];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_eventId forKey:kCodingKeyEventId];
    [coder encodeInt64:_originServerTs forKey:kCodingKeyOriginServerTs];
    [coder encodeBool:_isEncrypted forKey:kCodingKeyIsEncrypted];
    [coder encodeObject:_sender forKey:kCodingKeySender];
    
    // Build last message sensitive data
    NSMutableDictionary *lastMessageDictionary = [NSMutableDictionary dictionary];
    if (_text)
    {
        lastMessageDictionary[kCodingKeyText] = _text;
    }
    if (_attributedText)
    {
        lastMessageDictionary[kCodingKeyAttributedText] = _attributedText;
    }
    if (_others)
    {
        lastMessageDictionary[kCodingKeyOthers] = _others;
    }
    
    // And encrypt it if necessary
    if (_isEncrypted)
    {
        NSData *lastMessageData = [NSKeyedArchiver archivedDataWithRootObject:lastMessageDictionary];
        NSData *lastMessageEncryptedData = [self encrypt:lastMessageData];
        
        if (lastMessageEncryptedData)
        {
            [coder encodeObject:lastMessageEncryptedData forKey:kCodingKeyEncryptedData];
        }
    }
    else
    {
        [coder encodeObject:lastMessageDictionary forKey:kCodingKeyData];
    }
}

#pragma mark - Data encryption

/**
 The AES-256 key used for encrypting MXRoomSummary sensitive data.
 
 @return the encryption key if encryption is needed. Nil otherwise.
 */
- (MXAesKeyData *)encryptionKey
{
    // It is up to the app to provide a key for additional encryption
    MXKeyData * keyData =  [[MXKeyProvider sharedInstance] keyDataForDataOfType:MXRoomLastMessageDataType
                                                                    isMandatory:NO
                                                                expectedKeyType:kAes];
    if (keyData && [keyData isKindOfClass:[MXAesKeyData class]])
    {
        return (MXAesKeyData *)keyData;
    }
    
    return nil;
}

- (NSData*)encrypt:(NSData*)data
{
    MXAesKeyData *aesKey = self.encryptionKey;
    if (aesKey)
    {
        return [MXAes encrypt:data aesKey:aesKey.key iv:aesKey.iv error:nil];
    }

    MXLogWarning(@"[MXRoomLastMessage] encryptData: no key method provided for encryption.");
    return data;
}

- (NSData*)decrypt:(NSData*)data
{
    MXAesKeyData *aesKey = self.encryptionKey;
    if (aesKey)
    {
        return [MXAes decrypt:data aesKey:aesKey.key iv:aesKey.iv error:nil];
    }

    MXLogWarning(@"[MXRoomLastMessage] decryptData: no key method provided for decryption.");
    return data;
}

@end

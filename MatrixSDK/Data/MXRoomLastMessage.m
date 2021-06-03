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

#import <Security/Security.h>
#import <CommonCrypto/CommonCryptor.h>

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
        _others = lastMessageDictionary[kCodingKeyOthers];
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
 */
+ (NSData*)encryptionKey
{
    NSData *encryptionKey;

    // Create a dictionary to look up the key in the keychain
    NSDictionary *searchDict = @{
                                 (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                 (__bridge id)kSecAttrService: @"org.matrix.sdk.keychain",
                                 (__bridge id)kSecAttrAccount: @"MXRoomSummary",
                                 (__bridge id)kSecReturnData: (__bridge id)kCFBooleanTrue,
                                 };

    // Make the search
    CFDataRef foundKey = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)searchDict, (CFTypeRef*)&foundKey);

    if (status == errSecSuccess)
    {
        // Use the found key
        encryptionKey = (__bridge NSData*)(foundKey);
    }
    else if (status == errSecItemNotFound)
    {
        MXLogDebug(@"[MXRoomLastMessage] encryptionKey: Generate the key and store it to the keychain");

        // There is not yet a key in the keychain
        // Generate an AES key
        NSMutableData *newEncryptionKey = [[NSMutableData alloc] initWithLength:kCCKeySizeAES256];
        int retval = SecRandomCopyBytes(kSecRandomDefault, kCCKeySizeAES256, newEncryptionKey.mutableBytes);
        if (retval == 0)
        {
            encryptionKey = [NSData dataWithData:newEncryptionKey];

            // Store it to the keychain
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:searchDict];
            dict[(__bridge id)kSecValueData] = encryptionKey;

            status = SecItemAdd((__bridge CFDictionaryRef)dict, NULL);
            if (status != errSecSuccess)
            {
                // TODO: The iOS 10 simulator returns the -34018 (errSecMissingEntitlement) error.
                // We need to fix it but there is no issue with the app on real device nor with iOS 9 simulator.
                MXLogDebug(@"[MXRoomLastMessage] encryptionKey: SecItemAdd failed. status: %i", (int)status);
            }
        }
        else
        {
            MXLogDebug(@"[MXRoomLastMessage] encryptionKey: Cannot generate key. retval: %i", retval);
        }
    }
    else
    {
        MXLogDebug(@"[MXRoomLastMessage] encryptionKey: Keychain failed. OSStatus: %i", (int)status);
    }
    
    if (foundKey)
    {
        CFRelease(foundKey);
    }

    return encryptionKey;
}

- (NSData*)encrypt:(NSData*)data
{
    NSData *encryptedData;

    CCCryptorRef cryptor;
    CCCryptorStatus status;

    NSData *key = [MXRoomLastMessage encryptionKey];

    status = CCCryptorCreateWithMode(kCCDecrypt, kCCModeCTR, kCCAlgorithmAES,
                                     ccNoPadding, NULL, key.bytes, key.length,
                                     NULL, 0, 0, kCCModeOptionCTR_BE, &cryptor);
    if (status == kCCSuccess)
    {
        size_t bufferLength = CCCryptorGetOutputLength(cryptor, data.length, false);
        NSMutableData *buffer = [NSMutableData dataWithLength:bufferLength];

        size_t outLength;
        status |= CCCryptorUpdate(cryptor,
                                  data.bytes,
                                  data.length,
                                  [buffer mutableBytes],
                                  [buffer length],
                                  &outLength);

        status |= CCCryptorRelease(cryptor);

        if (status == kCCSuccess)
        {
            encryptedData = buffer;
        }
        else
        {
            MXLogDebug(@"[MXRoomLastMessage] encrypt: CCCryptorUpdate failed. status: %i", status);
        }
    }
    else
    {
        MXLogDebug(@"[MXRoomLastMessage] encrypt: CCCryptorCreateWithMode failed. status: %i", status);
    }

    return encryptedData;
}

- (NSData*)decrypt:(NSData*)encryptedData
{
    NSData *data;

    CCCryptorRef cryptor;
    CCCryptorStatus status;

    NSData *key = [MXRoomLastMessage encryptionKey];

    status = CCCryptorCreateWithMode(kCCDecrypt, kCCModeCTR, kCCAlgorithmAES,
                                     ccNoPadding, NULL, key.bytes, key.length,
                                     NULL, 0, 0, kCCModeOptionCTR_BE, &cryptor);
    if (status == kCCSuccess)
    {
        size_t bufferLength = CCCryptorGetOutputLength(cryptor, encryptedData.length, false);
        NSMutableData *buffer = [NSMutableData dataWithLength:bufferLength];

        size_t outLength;
        status |= CCCryptorUpdate(cryptor,
                                  encryptedData.bytes,
                                  encryptedData.length,
                                  [buffer mutableBytes],
                                  [buffer length],
                                  &outLength);

        status |= CCCryptorRelease(cryptor);

        if (status == kCCSuccess)
        {
            data = buffer;
        }
        else
        {
            MXLogDebug(@"[MXRoomLastMessage] decrypt: CCCryptorUpdate failed. status: %i", status);
        }
    }
    else
    {
        MXLogDebug(@"[MXRoomLastMessage] decrypt: CCCryptorCreateWithMode failed. status: %i", status);
    }
    
    return data;
}


@end

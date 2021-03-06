//
//  NWPusher.m
//  Pusher
//
//  Copyright (c) 2012 noodlewerk. All rights reserved.
//

#import "NWPusher.h"
#import "NWSSLConnection.h"
#import "NWSecTools.h"
#import "NWNotification.h"


static NSString * const NWSandboxPushHost = @"gateway.sandbox.push.apple.com";
static NSString * const NWPushHost = @"gateway.push.apple.com";
static NSUInteger const NWPushPort = 2195;

@implementation NWPusher {
    NSUInteger _index;
}

#pragma mark - Connecting

- (BOOL)connectWithIdentity:(NWIdentityRef)identity error:(NSError *__autoreleasing *)error
{
    if (_connection) [_connection disconnect]; _connection = nil;
    NSString *host = [NWSecTools isSandboxIdentity:identity] ? NWSandboxPushHost : NWPushHost;
    NWSSLConnection *connection = [[NWSSLConnection alloc] initWithHost:host port:NWPushPort identity:identity];
    BOOL connected = [connection connectWithError:error];
    if (!connected) {
        return connected;
    }
    _connection = connection;
    return YES;
}

- (BOOL)connectWithPKCS12Data:(NSData *)data password:(NSString *)password error:(NSError *__autoreleasing *)error
{
    NWIdentityRef identity = [NWSecTools identityWithPKCS12Data:data password:password error:error];
    if (!identity) {
        return NO;
    }
    return [self connectWithIdentity:identity error:error];
}

- (BOOL)reconnectWithError:(NSError *__autoreleasing *)error
{
    if (!_connection) {
        return [NWErrorUtil noWithErrorCode:kNWErrorPushNotConnected error:error];
    }
    return [_connection connectWithError:error];
}

- (void)disconnect
{
    [_connection disconnect]; _connection = nil;
}

+ (instancetype)connectWithIdentity:(NWIdentityRef)identity error:(NSError **)error
{
    NWPusher *pusher = [[NWPusher alloc] init];
    return identity && [pusher connectWithIdentity:identity error:error] ? pusher : nil;
}

+ (instancetype)connectWithPKCS12Data:(NSData *)data password:(NSString *)password error:(NSError **)error
{
    NWPusher *pusher = [[NWPusher alloc] init];
    return data && [pusher connectWithPKCS12Data:data password:password error:error] ? pusher : nil;
}

#pragma mark - Pushing payload

- (BOOL)pushPayload:(NSString *)payload token:(NSString *)token identifier:(NSUInteger)identifier error:(NSError *__autoreleasing *)error
{
    return [self pushNotification:[[NWNotification alloc] initWithPayload:payload token:token identifier:identifier expiration:nil priority:0] type:kNWNotificationType2 error:error];
}

- (BOOL)pushNotification:(NWNotification *)notification type:(NWNotificationType)type error:(NSError *__autoreleasing *)error
{
    NSUInteger length = 0;
    NSData *data = [notification dataWithType:type];
    BOOL written = [_connection write:data length:&length error:error];
    if (!written) {
        return written;
    }
    if (length != data.length) {
        return [NWErrorUtil noWithErrorCode:kNWErrorPushWriteFail error:error];
    }
    return YES;
}

#pragma mark - Fetching failed

- (BOOL)fetchFailedIdentifier:(NSUInteger *)identifier apnError:(NSError *__autoreleasing *)apnError error:(NSError *__autoreleasing *)error
{
    *identifier = 0;
    NSMutableData *data = [NSMutableData dataWithLength:sizeof(uint8_t) * 2 + sizeof(uint32_t)];
    NSUInteger length = 0;
    BOOL read = [_connection read:data length:&length error:error];
    if (!length || !read) {
        return read;
    }
    uint8_t command = 0;
    [data getBytes:&command range:NSMakeRange(0, 1)];
    if (command != 8) {
        return [NWErrorUtil noWithErrorCode:kNWErrorPushResponseCommand error:error];
    }
    uint8_t status = 0;
    [data getBytes:&status range:NSMakeRange(1, 1)];
    uint32_t ID = 0;
    [data getBytes:&ID range:NSMakeRange(2, 4)];
    *identifier = htonl(ID);
    switch (status) {
        case 1: [NWErrorUtil noWithErrorCode:kNWErrorAPNProcessing error:apnError]; break;
        case 2: [NWErrorUtil noWithErrorCode:kNWErrorAPNMissingDeviceToken error:apnError]; break;
        case 3: [NWErrorUtil noWithErrorCode:kNWErrorAPNMissingTopic error:apnError]; break;
        case 4: [NWErrorUtil noWithErrorCode:kNWErrorAPNMissingPayload error:apnError]; break;
        case 5: [NWErrorUtil noWithErrorCode:kNWErrorAPNInvalidTokenSize error:apnError]; break;
        case 6: [NWErrorUtil noWithErrorCode:kNWErrorAPNInvalidTopicSize error:apnError]; break;
        case 7: [NWErrorUtil noWithErrorCode:kNWErrorAPNInvalidPayloadSize error:apnError]; break;
        case 8: [NWErrorUtil noWithErrorCode:kNWErrorAPNInvalidTokenContent error:apnError]; break;
        case 10: [NWErrorUtil noWithErrorCode:kNWErrorAPNShutdown error:apnError]; break;
        default: [NWErrorUtil noWithErrorCode:kNWErrorAPNUnknownErrorCode error:apnError]; break;
    }
    return YES;
}

- (NSArray *)fetchFailedIdentifierErrorPairsWithMax:(NSUInteger)max error:(NSError *__autoreleasing *)error
{
    NSMutableArray *pairs = @[].mutableCopy;
    for (NSUInteger i = 0; i < max; i++) {
        NSUInteger identifier = 0;
        NSError *apnError = nil;
        BOOL fetched = [self fetchFailedIdentifier:&identifier apnError:&apnError error:error];
        if (!fetched) {
            return nil;
        }
        if (!apnError) {
            break;
        }
        [pairs addObject:@[@(identifier), apnError]];
    }
    return pairs;
}

#pragma mark - Deprecated

- (NWError)connectWithIdentity:(NWIdentityRef)identity
{
    NSError *error = nil;
    return [self connectWithIdentity:identity error:&error] ? kNWSuccess : error.code;
}

- (NWError)connectWithPKCS12Data:(NSData *)data password:(NSString *)password
{
    NSError *error = nil;
    return [self connectWithPKCS12Data:data password:password error:&error] ? kNWSuccess : error.code;
}

- (NWError)reconnect
{
    NSError *error = nil;
    return [self reconnectWithError:&error] ? kNWSuccess : error.code;
}

- (NWError)pushPayload:(NSString *)payload token:(NSString *)token identifier:(NSUInteger)identifier
{
    NSError *error = nil;
    return [self pushPayload:payload token:token identifier:identifier error:&error] ? kNWSuccess : error.code;
}

- (NWError)pushNotification:(NWNotification *)notification type:(NWNotificationType)type
{
    NSError *error = nil;
    return [self pushNotification:notification type:type error:&error] ? kNWSuccess : error.code;
}

- (NWError)fetchFailedIdentifier:(NSUInteger *)identifier apnError:(NWError *)apnErrorCode
{
    NSError *error = nil;
    NSError *apnError = nil;
    BOOL fetched = [self fetchFailedIdentifier:identifier apnError:&apnError error:&error];
    if (apnErrorCode && apnError) *apnErrorCode = apnError.code;
    return fetched ? kNWSuccess : error.code;
}

@end

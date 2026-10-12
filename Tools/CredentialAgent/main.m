// Protocol v1 is frozen. Releases reuse the exact signed executable, never rebuild it.
// No daemon, elevated rights, shell commands, disk secrets, or shared listening socket.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <unistd.h>

#ifndef STUDIO_REQUIREMENT
#error The build must supply the pinned public signing requirement
#endif

static const NSUInteger limit = 16 * 1024 * 1024;

static BOOL authorizedParent(void) {
    pid_t parent = getppid();
    if (parent <= 1) return NO;
    SecCodeRef code = NULL;
    SecRequirementRef requirement = NULL;
    NSDictionary *attributes = @{(__bridge NSString *)kSecGuestAttributePid: @(parent)};
    OSStatus status = SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef)attributes, 0, &code);
    if (status == errSecSuccess)
        status = SecRequirementCreateWithString(CFSTR(STUDIO_REQUIREMENT), 0, &requirement);
    if (status == errSecSuccess) status = SecCodeCheckValidity(code, 0, requirement);
    if (code) CFRelease(code);
    if (requirement) CFRelease(requirement);
    return status == errSecSuccess && parent == getppid();
}

static NSData *readRequest(void) {
    NSMutableData *data = [NSMutableData data];
    NSFileHandle *input = [NSFileHandle fileHandleWithStandardInput];
    for (;;) {
        NSData *part = [input readDataOfLength:65536];
        if (!part.length) break;
        if (data.length + part.length > limit) return nil;
        [data appendData:part];
    }
    return data;
}

static SecAccessRef applicationAccess(OSStatus *status) {
    SecAccessRef access = NULL;
    *status = SecAccessCreate(CFSTR("MSSQL Studio · Kayıtlı bağlantı"), NULL, &access);
    return access;
}

static BOOL validAccount(id account) {
    return [account isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:account] != nil;
}

static NSDictionary *perform(NSDictionary *request) {
    if (![request[@"protocol"] isEqual:@1]) return @{@"status": @(errSecParam)};
    NSString *operation = request[@"operation"];
    NSString *service = @"local.mssqlstudio.servers";
    SecKeychainRef fixture = NULL;
    id testPath = request[@"testKeychain"];
    if (testPath) {
        // Explicitly scoped synthetic fixtures; production clients never send these fields.
        NSString *testService = request[@"testService"];
        if (![testPath isKindOfClass:NSString.class] ||
            ![testService isKindOfClass:NSString.class] ||
            ![testService hasPrefix:@"local.mssqlstudio.signing-test."] ||
            ![[testPath lastPathComponent] hasPrefix:@"MSSQLStudio-signing-test-"])
            return @{@"status": @(errSecParam)};
        OSStatus opened = SecKeychainOpen([testPath fileSystemRepresentation], &fixture);
        if (opened != errSecSuccess) return @{@"status": @(opened)};
        service = testService;
        SecKeychainSetUserInteractionAllowed(false);
    }
    NSMutableDictionary *query = [@{(__bridge NSString *)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge NSString *)kSecAttrService: service} mutableCopy];
    if (fixture) {
        query[(__bridge NSString *)kSecMatchSearchList] = @[(__bridge id)fixture];
        query[(__bridge NSString *)kSecUseAuthenticationUI] = (__bridge id)kSecUseAuthenticationUIFail;
    }
    OSStatus status = errSecParam;
    NSMutableArray *records = [NSMutableArray array];
    NSUInteger count = 0, bytes = 0;
    NSString *account = request[@"account"];
    if ([operation isEqual:@"save"] && validAccount(account)) {
        NSString *encoded = request[@"data"];
        NSData *data = [encoded isKindOfClass:NSString.class] ? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
        NSDictionary *record = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (data.length > 0 && data.length <= 1024 * 1024 && [record isKindOfClass:NSDictionary.class] &&
            [record[@"profile"] isKindOfClass:NSDictionary.class] &&
            [record[@"profile"][@"id"] isEqual:account] && [record[@"password"] isKindOfClass:NSString.class]) {
            query[(__bridge NSString *)kSecAttrAccount] = account;
            SecAccessRef access = applicationAccess(&status);
            if (status == errSecSuccess) {
                NSMutableDictionary *attributes = [query mutableCopy];
                if (fixture) attributes[(__bridge NSString *)kSecUseKeychain] = (__bridge id)fixture;
                attributes[(__bridge NSString *)kSecAttrAccess] = (__bridge id)access;
                attributes[(__bridge NSString *)kSecAttrLabel] = @"MSSQL Studio · Kayıtlı bağlantı";
                attributes[(__bridge NSString *)kSecValueData] = data;
                status = SecItemAdd((__bridge CFDictionaryRef)attributes, NULL);
                if (status == errSecDuplicateItem) {
                    // Never rewrite ACLs or partitions during ordinary password/profile updates.
                    NSDictionary *changes = @{(__bridge NSString *)kSecValueData: data};
                    status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)changes);
                }
                CFRelease(access);
            }
        }
    } else if ([operation isEqual:@"delete"] && validAccount(account)) {
        query[(__bridge NSString *)kSecAttrAccount] = account;
        status = SecItemDelete((__bridge CFDictionaryRef)query);
        if (status == errSecItemNotFound) status = errSecSuccess;
    } else if ([operation isEqual:@"list"] || [operation isEqual:@"renew"]) {
        NSMutableDictionary *lookup = [query mutableCopy];
        lookup[(__bridge NSString *)kSecReturnAttributes] = @YES;
        lookup[(__bridge NSString *)kSecMatchLimit] = (__bridge id)kSecMatchLimitAll;
        CFTypeRef result = NULL;
        status = SecItemCopyMatching((__bridge CFDictionaryRef)lookup, &result);
        if (status == errSecItemNotFound) status = errSecSuccess;
        NSArray *items = CFBridgingRelease(result);
        if (status == errSecSuccess) for (NSDictionary *item in items) {
            id idValue = item[(__bridge NSString *)kSecAttrAccount];
            if (!validAccount(idValue)) continue;
            NSMutableDictionary *itemQuery = [query mutableCopy];
            itemQuery[(__bridge NSString *)kSecAttrAccount] = idValue;
            if ([operation isEqual:@"renew"]) {
                SecAccessRef access = applicationAccess(&status);
                if (status == errSecSuccess) {
                    status = SecItemUpdate((__bridge CFDictionaryRef)itemQuery,
                        (__bridge CFDictionaryRef)@{(__bridge NSString *)kSecAttrAccess: (__bridge id)access});
                    CFRelease(access);
                }
                if (status != errSecSuccess) break;
                count++;
            } else {
                itemQuery[(__bridge NSString *)kSecReturnData] = @YES;
                CFTypeRef value = NULL;
                status = SecItemCopyMatching((__bridge CFDictionaryRef)itemQuery, &value);
                NSData *data = CFBridgingRelease(value);
                if (status != errSecSuccess) break;
                if (![data isKindOfClass:NSData.class] || data.length > 1024 * 1024 ||
                    bytes + data.length > limit / 2) { status = errSecDataTooLarge; break; }
                bytes += data.length;
                [records addObject:[data base64EncodedStringWithOptions:0]];
            }
        }
    }
    if (fixture) CFRelease(fixture);
    // An unsuccessful list never returns a partial collection of secrets.
    return @{@"status": @(status), @"records": status == errSecSuccess ? records : @[], @"count": @(count)};
}

int main(void) {
    @autoreleasepool {
        if (!authorizedParent()) return 77;
        @try {
            NSData *data = readRequest();
            id request = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            NSDictionary *response = [request isKindOfClass:NSDictionary.class] && authorizedParent()
                ? perform(request) : @{@"status": @(errSecParam)};
            NSData *output = [NSJSONSerialization dataWithJSONObject:response options:0 error:NULL];
            [[NSFileHandle fileHandleWithStandardOutput] writeData:output];
            return 0;
        } @catch (NSException *exception) {
            // Never log exceptions/request data; they may contain credentials.
            return 1;
        }
    }
}

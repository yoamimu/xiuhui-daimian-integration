#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <Security/Security.h>

#include <errno.h>
#include <sys/sysctl.h>
#include <unistd.h>

#ifndef XH_OFFLINE_ACTIVATION
#define XH_OFFLINE_ACTIVATION 0
#endif

#if !XH_OFFLINE_ACTIVATION && !defined(XH_ACTIVATION_SERVER_URL)
#error "XH_ACTIVATION_SERVER_URL must be provided for online activation"
#endif

#ifndef XH_LICENSE_PUBLIC_KEY_B64
#error "XH_LICENSE_PUBLIC_KEY_B64 must be provided by the build script"
#endif

static NSString *const XHAppID = @"com.yoamimu.xiuhui-daimian.inkscape";
#if defined(XH_TEST_BUILD) && XH_TEST_BUILD
static NSString *const XHKeychainService = @"com.yoamimu.xiuhui.activation.tests";
#else
static NSString *const XHKeychainService = @"com.yoamimu.xiuhui.activation";
#endif
static NSString *const XHPublicKeyBase64 = XH_LICENSE_PUBLIC_KEY_B64;
#if !XH_OFFLINE_ACTIVATION
static NSString *const XHServerURL = XH_ACTIVATION_SERVER_URL;
static const NSTimeInterval XHNetworkTimeout = 7.0;

typedef NS_ENUM(NSInteger, XHRequestKind) {
    XHRequestKindSuccess,
    XHRequestKindServerRejection,
    XHRequestKindNetworkFailure,
};

@interface XHServerResult : NSObject
@property(nonatomic) XHRequestKind kind;
@property(nonatomic, copy) NSString *message;
@property(nonatomic, copy) NSString *licenseToken;
@property(nonatomic, copy) NSString *normalizedCode;
@end

@implementation XHServerResult
@end
#endif

static NSData *XHKeychainData(NSString *account) {
    NSDictionary *query = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : XHKeychainService,
        (__bridge id)kSecAttrAccount : account,
        (__bridge id)kSecReturnData : @YES,
        (__bridge id)kSecMatchLimit : (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || result == NULL) return nil;
    return CFBridgingRelease(result);
}

static NSString *XHKeychainString(NSString *account) {
    NSData *data = XHKeychainData(account);
    if (!data) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static BOOL XHSetKeychainString(NSString *account, NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *base = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : XHKeychainService,
        (__bridge id)kSecAttrAccount : account,
    };
    OSStatus status = SecItemUpdate(
        (__bridge CFDictionaryRef)base,
        (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData : data}
    );
    if (status == errSecItemNotFound) {
        NSMutableDictionary *item = [base mutableCopy];
        item[(__bridge id)kSecValueData] = data;
        item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
        status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    }
    return status == errSecSuccess;
}

static void XHDeleteKeychainItem(NSString *account) {
    NSDictionary *query = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : XHKeychainService,
        (__bridge id)kSecAttrAccount : account,
    };
    SecItemDelete((__bridge CFDictionaryRef)query);
}

static NSString *XHSHA256(NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [hex appendFormat:@"%02x", digest[index]];
    }
    return hex;
}

static NSString *XHHardwareUUID(void) {
    io_service_t platform = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice")
    );
    if (platform == IO_OBJECT_NULL) return nil;
    CFTypeRef value = IORegistryEntryCreateCFProperty(
        platform, CFSTR("IOPlatformUUID"), kCFAllocatorDefault, 0
    );
    IOObjectRelease(platform);
    if (!value || CFGetTypeID(value) != CFStringGetTypeID()) {
        if (value) CFRelease(value);
        return nil;
    }
    return CFBridgingRelease(value);
}

static NSString *XHDeviceID(void) {
    NSString *hardwareUUID = XHHardwareUUID();
    if (!hardwareUUID.length) {
        hardwareUUID = XHKeychainString(@"fallback-device-id");
        if (!hardwareUUID.length) {
            hardwareUUID = NSUUID.UUID.UUIDString;
            XHSetKeychainString(@"fallback-device-id", hardwareUUID);
        }
    }
    return XHSHA256([NSString stringWithFormat:@"xiuhui-device-v1|%@|%@", XHAppID, hardwareUUID]);
}

#if !XH_OFFLINE_ACTIVATION
static NSString *XHMachineModel(void) {
    size_t size = 0;
    if (sysctlbyname("hw.model", NULL, &size, NULL, 0) != 0 || size == 0) return @"Mac";
    char *buffer = calloc(size, 1);
    if (!buffer) return @"Mac";
    NSString *model = @"Mac";
    if (sysctlbyname("hw.model", buffer, &size, NULL, 0) == 0) {
        model = [NSString stringWithUTF8String:buffer] ?: @"Mac";
    }
    free(buffer);
    return model;
}

static NSString *XHArchitecture(void) {
#if defined(__arm64__)
    return @"arm64";
#elif defined(__x86_64__)
    return @"x86_64";
#else
    return @"unknown";
#endif
}

static NSString *XHNormalizeCode(NSString *rawCode) {
    NSString *upper = rawCode.uppercaseString ?: @"";
    NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
    NSMutableString *compact = [NSMutableString string];
    for (NSUInteger index = 0; index < upper.length; index++) {
        unichar character = [upper characterAtIndex:index];
        if ([allowed characterIsMember:character]) {
            [compact appendFormat:@"%C", character];
        }
    }
    if (compact.length == 14 && [compact hasPrefix:@"XH"]) {
        return [NSString stringWithFormat:@"XH-%@-%@-%@",
                [compact substringWithRange:NSMakeRange(2, 4)],
                [compact substringWithRange:NSMakeRange(6, 4)],
                [compact substringWithRange:NSMakeRange(10, 4)]];
    }
    return upper;
}
#endif

#if XH_OFFLINE_ACTIVATION
static NSString *XHBase64URLEncode(NSData *data) {
    NSString *value = [data base64EncodedStringWithOptions:0];
    value = [value stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    value = [value stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"="]];
}
#endif

static NSData *XHBase64URLDecode(NSString *value) {
    NSString *base64 = [[value stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
                        stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    NSUInteger padding = (4 - base64.length % 4) % 4;
    if (padding) base64 = [base64 stringByPaddingToLength:base64.length + padding withString:@"=" startingAtIndex:0];
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

static SecKeyRef XHLicensePublicKey(void) {
    static SecKeyRef publicKey = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSData *keyData = [[NSData alloc] initWithBase64EncodedString:XHPublicKeyBase64 options:0];
        if (keyData.length != 65) return;
        NSDictionary *attributes = @{
            (__bridge id)kSecAttrKeyType : (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
            (__bridge id)kSecAttrKeyClass : (__bridge id)kSecAttrKeyClassPublic,
            (__bridge id)kSecAttrKeySizeInBits : @256,
        };
        CFErrorRef error = NULL;
        publicKey = SecKeyCreateWithData(
            (__bridge CFDataRef)keyData,
            (__bridge CFDictionaryRef)attributes,
            &error
        );
        if (error) CFRelease(error);
    });
    return publicKey;
}

static NSDictionary *XHVerifiedPayload(
    NSString *token,
    NSString *deviceID,
    BOOL requireLease,
    NSInteger requiredVersion
) {
    NSArray<NSString *> *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 2) return nil;
    NSData *payloadData = XHBase64URLDecode(parts[0]);
    NSData *signatureData = XHBase64URLDecode(parts[1]);
    SecKeyRef publicKey = XHLicensePublicKey();
    if (!payloadData || !signatureData || !publicKey) return nil;

    CFErrorRef verificationError = NULL;
    BOOL signatureValid = SecKeyVerifySignature(
        publicKey,
        kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
        (__bridge CFDataRef)payloadData,
        (__bridge CFDataRef)signatureData,
        &verificationError
    );
    if (verificationError) CFRelease(verificationError);
    if (!signatureValid) return nil;

    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:nil];
    if (![payload isKindOfClass:NSDictionary.class]) return nil;
    if (![payload[@"app_id"] isEqual:XHAppID]) return nil;
    if (![payload[@"device_id"] isEqual:deviceID]) return nil;
    if ([payload[@"version"] integerValue] != requiredVersion) return nil;

    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSTimeInterval issuedAt = [payload[@"issued_at"] doubleValue];
    NSTimeInterval startsAt = [payload[@"starts_at"] doubleValue];
    NSTimeInterval expiresAt = [payload[@"expires_at"] doubleValue];
    NSTimeInterval leaseUntil = [payload[@"lease_until"] doubleValue];
    if (issuedAt <= 0 || issuedAt > now + 300 || expiresAt <= now) return nil;
    if (startsAt > 0 && startsAt > now + 300) return nil;
    if (requireLease && leaseUntil <= now) return nil;

#if !defined(XH_TEST_BUILD) || !XH_TEST_BUILD
    NSTimeInterval previousSeen = [XHKeychainString(@"last-seen-time") doubleValue];
    if (previousSeen > 0 && now + 300 < previousSeen) return nil;
    if (now > previousSeen) {
        XHSetKeychainString(@"last-seen-time", [NSString stringWithFormat:@"%.0f", now]);
    }
#endif
    return payload;
}

#if !XH_OFFLINE_ACTIVATION
static NSURL *XHEndpointURL(NSString *endpoint) {
    NSString *base = [XHServerURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/v1/%@", base, endpoint]];
}

static XHServerResult *XHRequestServer(NSString *endpoint, NSString *activationCode, NSString *deviceID) {
    XHServerResult *result = [XHServerResult new];
    result.normalizedCode = XHNormalizeCode(activationCode);
    NSURL *url = XHEndpointURL(endpoint);
    if (!url || ![url.scheme.lowercaseString isEqualToString:@"https"]) {
#if defined(XH_ALLOW_INSECURE_HTTP) && XH_ALLOW_INSECURE_HTTP
        BOOL localHTTP = [url.scheme.lowercaseString isEqualToString:@"http"]
            && ([url.host isEqualToString:@"127.0.0.1"] || [url.host isEqualToString:@"localhost"]);
        if (!localHTTP) {
#endif
            result.kind = XHRequestKindServerRejection;
            result.message = @"授权服务器地址不安全，请联系销售方更新软件。";
            return result;
#if defined(XH_ALLOW_INSECURE_HTTP) && XH_ALLOW_INSECURE_HTTP
        }
#endif
    }

    NSDictionary *body = @{
        @"activation_code" : result.normalizedCode,
        @"device_id" : deviceID,
        @"device_label" : XHMachineModel(),
        @"app_version" : [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown",
        @"macos_version" : NSProcessInfo.processInfo.operatingSystemVersionString ?: @"unknown",
        @"architecture" : XHArchitecture(),
    };
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = bodyData;
    request.timeoutInterval = XHNetworkTimeout;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = XHNetworkTimeout;
    configuration.timeoutIntervalForResource = XHNetworkTimeout + 1;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *responseData = nil;
    __block NSHTTPURLResponse *httpResponse = nil;
    __block NSError *networkError = nil;
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        responseData = data;
        httpResponse = (NSHTTPURLResponse *)response;
        networkError = error;
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    long waitResult = dispatch_semaphore_wait(
        semaphore,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)((XHNetworkTimeout + 2) * NSEC_PER_SEC))
    );
    [session finishTasksAndInvalidate];

    if (waitResult != 0 || networkError || !httpResponse) {
        [task cancel];
        result.kind = XHRequestKindNetworkFailure;
        result.message = @"暂时无法连接授权服务器，请检查网络后重试。";
        return result;
    }

    NSDictionary *json = nil;
    if (responseData.length) {
        id object = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
        if ([object isKindOfClass:NSDictionary.class]) json = object;
    }
    if (httpResponse.statusCode == 200 && [json[@"ok"] boolValue]) {
        NSString *token = json[@"license_token"];
        if (![token isKindOfClass:NSString.class] || !XHVerifiedPayload(token, deviceID, YES, 1)) {
            result.kind = XHRequestKindServerRejection;
            result.message = @"授权服务器返回的数据无法验证，请联系销售方。";
            return result;
        }
        result.kind = XHRequestKindSuccess;
        result.licenseToken = token;
        result.message = @"授权有效。";
        return result;
    }

    if (httpResponse.statusCode == 429 || httpResponse.statusCode >= 500) {
        result.kind = XHRequestKindNetworkFailure;
        result.message = @"授权服务器暂时繁忙，将使用有效的本地授权继续启动。";
        return result;
    }

    result.kind = XHRequestKindServerRejection;
    NSString *message = json[@"message"];
    result.message = [message isKindOfClass:NSString.class] && message.length
        ? message
        : @"授权验证失败，请检查激活码后重试。";
    return result;
}
#endif

static void XHShowMessage(NSString *title, NSString *message) {
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    alert.informativeText = message ?: @"";
    [alert addButtonWithTitle:@"确定"];
    [NSApp activateIgnoringOtherApps:YES];
    [alert runModal];
}

#if !XH_OFFLINE_ACTIVATION
static NSString *XHPromptForActivationCode(NSString *existingCode, NSString *message) {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"激活绣绘";
    alert.informativeText = message.length
        ? message
        : @"请输入付款后获得的唯一激活码。授权将绑定这台 Mac。";
    [alert addButtonWithTitle:@"激活并打开"];
    [alert addButtonWithTitle:@"退出"];

    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 54)];
    NSTextField *label = [NSTextField labelWithString:@"激活码"];
    label.frame = NSMakeRect(0, 34, 360, 18);
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 360, 28)];
    input.placeholderString = @"XH-ABCD-EFGH-JKLM";
    input.stringValue = existingCode ?: @"";
    input.font = [NSFont monospacedSystemFontOfSize:14 weight:NSFontWeightMedium];
    [accessory addSubview:label];
    [accessory addSubview:input];
    alert.accessoryView = accessory;

    [NSApp activateIgnoringOtherApps:YES];
    NSModalResponse response = [alert runModal];
    if (response != NSAlertFirstButtonReturn) return nil;
    return XHNormalizeCode(input.stringValue);
}

static BOOL XHObtainValidLicense(NSString *deviceID) {
    NSString *storedCode = XHKeychainString(@"activation-code");
    NSString *storedToken = XHKeychainString(@"license-token");
    NSString *promptMessage = @"";

    if (storedCode.length) {
        XHServerResult *validation = XHRequestServer(@"validate", storedCode, deviceID);
        if (validation.kind == XHRequestKindSuccess) {
            XHSetKeychainString(@"activation-code", validation.normalizedCode);
            XHSetKeychainString(@"license-token", validation.licenseToken);
            return YES;
        }
        if (validation.kind == XHRequestKindNetworkFailure
            && storedToken.length
            && XHVerifiedPayload(storedToken, deviceID, YES, 1)) {
            return YES;
        }
        if (validation.kind == XHRequestKindServerRejection) {
            XHDeleteKeychainItem(@"license-token");
        }
        promptMessage = validation.message;
    }

    while (YES) {
        NSString *candidate = XHPromptForActivationCode(storedCode, promptMessage);
        if (!candidate) return NO;
        if (candidate.length < 17) {
            promptMessage = @"激活码格式不正确，请输入类似 XH-ABCD-EFGH-JKLM 的完整激活码。";
            continue;
        }
        XHServerResult *activation = XHRequestServer(@"activate", candidate, deviceID);
        if (activation.kind == XHRequestKindSuccess) {
            XHSetKeychainString(@"activation-code", activation.normalizedCode);
            XHSetKeychainString(@"license-token", activation.licenseToken);
            return YES;
        }
        storedCode = candidate;
        promptMessage = activation.message;
    }
}
#else
static NSString *XHDeviceRequestCode(NSString *deviceID) {
    if (deviceID.length != 64) return nil;
    NSMutableData *data = [NSMutableData dataWithCapacity:32];
    for (NSUInteger index = 0; index < deviceID.length; index += 2) {
        NSString *pair = [deviceID substringWithRange:NSMakeRange(index, 2)];
        unsigned int byte = 0;
        NSScanner *scanner = [NSScanner scannerWithString:pair];
        if (![scanner scanHexInt:&byte]) return nil;
        uint8_t value = (uint8_t)byte;
        [data appendBytes:&value length:1];
    }
    return [@"XHD-" stringByAppendingString:XHBase64URLEncode(data)];
}

static NSString *XHCompactLicenseToken(NSString *value) {
    NSArray<NSString *> *parts = [value componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [parts componentsJoinedByString:@""];
}

static BOOL XHCopyDeviceCode(NSString *deviceCode) {
    if (!deviceCode.length) return NO;
    NSData *data = [deviceCode dataUsingEncoding:NSUTF8StringEncoding];
    NSPipe *pipe = [NSPipe pipe];
    NSTask *pbcopy = [NSTask new];
    pbcopy.executableURL = [NSURL fileURLWithPath:@"/usr/bin/pbcopy"];
    pbcopy.standardInput = pipe;
    NSError *taskError = nil;
    [pbcopy launchAndReturnError:&taskError];
    if (!taskError) {
        [[pipe fileHandleForWriting] writeData:data];
        [[pipe fileHandleForWriting] closeFile];
        [pbcopy waitUntilExit];
        if (pbcopy.terminationStatus == 0) return YES;
    }

    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard declareTypes:@[NSPasteboardTypeString] owner:nil];
    BOOL written = [pasteboard setString:deviceCode forType:NSPasteboardTypeString];
    NSString *check = [pasteboard stringForType:NSPasteboardTypeString];
    return written && [check isEqualToString:deviceCode];
}

@interface XHDeviceCodeField : NSTextField
@property(nonatomic, copy) NSString *deviceCode;
@end

@implementation XHDeviceCodeField
- (void)copy:(id)sender {
    (void)sender;
    XHCopyDeviceCode(self.deviceCode ?: self.stringValue);
}
@end

@interface XHLicenseInputTextView : NSTextView
@end

@implementation XHLicenseInputTextView
- (void)paste:(id)sender {
    (void)sender;
    NSString *value = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
    if (value.length) self.string = value;
}
- (void)readClipboard:(id)sender {
    (void)sender;
    NSString *value = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
    if (value.length) {
        self.string = value;
        [self.window makeFirstResponder:self];
    }
}
@end

static NSString *XHPromptForOfflineLicense(NSString *deviceCode, NSString *message) {
    NSString *enteredToken = @"";
    NSString *promptMessage = message ?: @"";

    while (YES) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"激活绣绘";
        alert.informativeText = promptMessage.length
            ? promptMessage
            : @"请把设备码发给销售方，再粘贴收到的离线授权码。授权只适用于这台 Mac。";
        [alert addButtonWithTitle:@"激活并打开"];
        [alert addButtonWithTitle:@"复制设备码"];
        [alert addButtonWithTitle:@"退出"];

        NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 150)];
        NSTextField *deviceLabel = [NSTextField labelWithString:@"本机设备码"];
        deviceLabel.frame = NSMakeRect(0, 126, 500, 18);

        XHDeviceCodeField *deviceField = [[XHDeviceCodeField alloc] initWithFrame:NSMakeRect(0, 96, 500, 26)];
        deviceField.stringValue = deviceCode ?: @"";
        deviceField.deviceCode = deviceCode ?: @"";
        deviceField.alignment = NSTextAlignmentLeft;
        deviceField.target = deviceField;
        deviceField.action = @selector(copy:);
        deviceField.editable = YES;
        deviceField.selectable = YES;
        deviceField.bordered = YES;
        deviceField.drawsBackground = YES;
        deviceField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
        deviceField.toolTip = @"可点击后按 Command-C 复制设备码";

        NSTextField *licenseLabel = [NSTextField labelWithString:@"离线授权码"];
        licenseLabel.frame = NSMakeRect(0, 68, 500, 18);

        NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 500, 64)];
        scrollView.hasVerticalScroller = YES;
        scrollView.borderType = NSBezelBorder;
        XHLicenseInputTextView *input = [[XHLicenseInputTextView alloc] initWithFrame:scrollView.bounds];
        input.string = enteredToken;
        input.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        input.textContainerInset = NSMakeSize(6, 6);
        input.automaticQuoteSubstitutionEnabled = NO;
        input.automaticDashSubstitutionEnabled = NO;
        input.automaticTextReplacementEnabled = NO;
        scrollView.documentView = input;

        NSButton *pasteButton = [NSButton buttonWithTitle:@"读取剪贴板" target:input action:@selector(readClipboard:)];
        pasteButton.frame = NSMakeRect(380, 68, 120, 22);
        pasteButton.bezelStyle = NSBezelStyleRounded;

        [accessory addSubview:deviceLabel];
        [accessory addSubview:deviceField];
        [accessory addSubview:licenseLabel];
        [accessory addSubview:pasteButton];
        [accessory addSubview:scrollView];
        alert.accessoryView = accessory;

        [NSApp activateIgnoringOtherApps:YES];
        NSModalResponse response = [alert runModal];
        enteredToken = input.string ?: @"";
        if (response == NSAlertFirstButtonReturn) {
            return XHCompactLicenseToken(enteredToken);
        }
        if (response == NSAlertSecondButtonReturn) {
            BOOL copied = XHCopyDeviceCode(deviceCode);
            promptMessage = copied
                ? @"设备码已复制。发给销售方取得授权码后，粘贴到下方。"
                : @"复制设备码失败。请点击设备码文字后按 Command-C，或重试。";
            continue;
        }
        return nil;
    }
}

static BOOL XHObtainValidOfflineLicense(NSString *deviceID) {
    NSString *storedToken = XHKeychainString(@"license-token");
    NSDictionary *storedPayload = storedToken.length
        ? XHVerifiedPayload(storedToken, deviceID, YES, 2)
        : nil;
    if (storedPayload && [storedPayload[@"offline"] boolValue]) return YES;

    if (storedToken.length) XHDeleteKeychainItem(@"license-token");
    NSString *deviceCode = XHDeviceRequestCode(deviceID);
    if (!deviceCode.length) return NO;
    NSString *message = storedToken.length
        ? @"原授权已过期、尚未生效或不属于这台 Mac，请联系销售方重新获取。"
        : @"";

    while (YES) {
        NSString *candidate = XHPromptForOfflineLicense(deviceCode, message);
        if (!candidate) return NO;
        if (candidate.length < 80) {
            message = @"授权码不完整，请重新复制销售方发来的全部内容。";
            continue;
        }
        NSDictionary *payload = XHVerifiedPayload(candidate, deviceID, YES, 2);
        if (!payload || ![payload[@"offline"] boolValue]) {
            message = @"授权码无效、已过期或不属于这台 Mac，请检查后重试。";
            continue;
        }
        if (!XHSetKeychainString(@"license-token", candidate)) {
            message = @"无法将授权保存到系统钥匙串，请检查钥匙串访问权限。";
            continue;
        }
        XHDeleteKeychainItem(@"activation-code");
        NSString *expiry = [payload[@"expires_on"] isKindOfClass:NSString.class]
            ? payload[@"expires_on"]
            : @"一年后";
        XHShowMessage(@"绣绘已激活", [NSString stringWithFormat:@"授权仅限这台 Mac 使用，有效期至 %@。", expiry]);
        return YES;
    }
}
#endif

static int XHExecCore(int argc, const char *argv[]) {
    NSString *corePath = [NSBundle.mainBundle.bundlePath
        stringByAppendingPathComponent:@"Contents/MacOS/inkscape-core"];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:corePath]) {
        XHShowMessage(@"绣绘无法启动", @"主程序文件缺失或不可执行，请重新下载安装包。" );
        return 70;
    }

    // GTK's GPU renderer can crash in Cairo clip replay while drawing over
    // imported images, especially when a window spans or moves between
    // displays.  Prefer the Cairo renderer for predictable customer builds.
    // Respect an explicit environment override for diagnostics.
    if (!getenv("GSK_RENDERER")) setenv("GSK_RENDERER", "cairo", 1);

    char **coreArguments = calloc((size_t)argc + 1, sizeof(char *));
    if (!coreArguments) return 71;
    coreArguments[0] = strdup(corePath.fileSystemRepresentation);
    for (int index = 1; index < argc; index++) coreArguments[index] = strdup(argv[index]);
    coreArguments[argc] = NULL;
    execv(corePath.fileSystemRepresentation, coreArguments);

    NSString *message = [NSString stringWithFormat:@"无法运行主程序：%s", strerror(errno)];
    XHShowMessage(@"绣绘无法启动", message);
    return 72;
}

#if defined(XH_TEST_BUILD) && XH_TEST_BUILD
static int XHRunTestCommand(int argc, const char *argv[]) {
#if XH_OFFLINE_ACTIVATION
    if (argc != 3 || strcmp(argv[1], "--xh-test-offline-token") != 0) return -1;
    NSString *token = [NSString stringWithUTF8String:argv[2]];
    NSString *deviceID = NSProcessInfo.processInfo.environment[@"XH_TEST_DEVICE_ID"];
    if (!deviceID.length) {
        fprintf(stderr, "XH_TEST_DEVICE_ID is required\n");
        return 90;
    }
    NSDictionary *payload = XHVerifiedPayload(token, deviceID, YES, 2);
    if (!payload || ![payload[@"offline"] boolValue]) {
        fprintf(stderr, "offline license rejected\n");
        return 11;
    }
    fprintf(stdout, "offline license valid through %s\n", [payload[@"expires_on"] UTF8String] ?: "unknown");
    return 0;
#else
    if (argc != 4 || strcmp(argv[1], "--xh-test-request") != 0) return -1;
    NSString *endpoint = [NSString stringWithUTF8String:argv[2]];
    NSString *code = [NSString stringWithUTF8String:argv[3]];
    NSString *deviceID = NSProcessInfo.processInfo.environment[@"XH_TEST_DEVICE_ID"];
    if (!deviceID.length) {
        fprintf(stderr, "XH_TEST_DEVICE_ID is required\n");
        return 90;
    }
    XHServerResult *result = XHRequestServer(endpoint, code, deviceID);
    fprintf(stdout, "%ld\t%s\n", (long)result.kind, result.message.UTF8String ?: "");
    return result.kind == XHRequestKindSuccess ? 0 : 10 + (int)result.kind;
#endif
}
#endif

int main(int argc, const char *argv[]) {
    @autoreleasepool {
#if defined(XH_TEST_BUILD) && XH_TEST_BUILD
        int testResult = XHRunTestCommand(argc, argv);
        if (testResult >= 0) return testResult;
#endif
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        NSString *deviceID = XHDeviceID();
        if (!deviceID.length) {
            XHShowMessage(@"绣绘无法启动", @"无法生成这台 Mac 的设备密钥，请联系销售方。" );
            return 73;
        }
#if defined(XH_TEST_BUILD) && XH_TEST_BUILD && !XH_OFFLINE_ACTIVATION
        NSString *automaticTestCode = NSProcessInfo.processInfo.environment[@"XH_TEST_ACTIVATION_CODE"];
        if (automaticTestCode.length) {
            XHServerResult *testActivation = XHRequestServer(@"activate", automaticTestCode, deviceID);
            if (testActivation.kind != XHRequestKindSuccess) {
                fprintf(stderr, "full-app activation failed: %s\n", testActivation.message.UTF8String ?: "");
                return 91;
            }
            return XHExecCore(argc, argv);
        }
#endif
#if XH_OFFLINE_ACTIVATION
        if (!XHObtainValidOfflineLicense(deviceID)) return 0;
#else
        if (!XHObtainValidLicense(deviceID)) return 0;
#endif
        [NSApp hide:nil];
        return XHExecCore(argc, argv);
    }
}

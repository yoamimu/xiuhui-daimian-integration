#import <Cocoa/Cocoa.h>

#include <sys/stat.h>

static NSString *const XHAppID = @"com.yoamimu.xiuhui-daimian.inkscape";
static NSInteger const XHLicenseVersion = 2;

static NSString *XHBase64URL(NSData *data) {
    NSString *value = [data base64EncodedStringWithOptions:0];
    value = [value stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    value = [value stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"="]];
}

static NSData *XHBase64URLDecode(NSString *value) {
    NSString *base64 = [[value stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
                        stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    NSUInteger padding = (4 - base64.length % 4) % 4;
    if (padding) {
        base64 = [base64 stringByPaddingToLength:base64.length + padding withString:@"=" startingAtIndex:0];
    }
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

static NSString *XHNormalizeDeviceID(NSString *rawCode) {
    NSString *compact = [[rawCode componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                         componentsJoinedByString:@""];
    if ([compact.uppercaseString hasPrefix:@"XHD-"]) {
        NSData *decoded = XHBase64URLDecode([compact substringFromIndex:4]);
        if (decoded.length != 32) return nil;
        const uint8_t *bytes = decoded.bytes;
        NSMutableString *hex = [NSMutableString stringWithCapacity:64];
        for (NSUInteger index = 0; index < decoded.length; index++) {
            [hex appendFormat:@"%02x", bytes[index]];
        }
        return hex;
    }
    if (compact.length != 64) return nil;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet];
    if ([compact rangeOfCharacterFromSet:invalid].location != NSNotFound) return nil;
    return compact.lowercaseString;
}

static NSString *XHCSVField(NSString *value) {
    NSString *escaped = [(value ?: @"") stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

@interface XHGeneratorDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTextField *customerField;
@property(nonatomic, strong) NSTextField *orderField;
@property(nonatomic, strong) NSTextField *deviceField;
@property(nonatomic, strong) NSDatePicker *datePicker;
@property(nonatomic, strong) NSTextView *licenseOutput;
@property(nonatomic, strong) NSTextField *statusLabel;
@end

@interface XHDeviceCodeField : NSTextField
@end

@implementation XHDeviceCodeField
- (void)paste:(id)sender {
    (void)sender;
    NSString *value = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
    if (value.length) self.stringValue = value;
}
@end

@implementation XHGeneratorDelegate

- (NSString *)privateKeyPath {
    NSString *configured = NSProcessInfo.processInfo.environment[@"XH_LICENSE_PRIVATE_KEY"];
    if (configured.length) return configured.stringByExpandingTildeInPath;
    return [NSHomeDirectory() stringByAppendingPathComponent:@"xiuhui-build/signing/activation/license_private_key.pem"];
}

- (NSString *)recordsPath {
    NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/绣绘授权生成器"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions : @0700}
                                                    error:nil];
    return [directory stringByAppendingPathComponent:@"授权记录.csv"];
}

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = frame;
    return label;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 660, 570)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.window.title = @"绣绘授权生成器";
    self.window.releasedWhenClosed = NO;
    [self.window center];

    NSView *content = self.window.contentView;
    NSTextField *title = [NSTextField labelWithString:@"绣绘离线授权"];
    title.frame = NSMakeRect(28, 518, 604, 28);
    title.font = [NSFont systemFontOfSize:22 weight:NSFontWeightSemibold];
    [content addSubview:title];

    NSTextField *subtitle = [NSTextField labelWithString:@"授权会绑定客户设备，并从付款日起有效一年。"];
    subtitle.frame = NSMakeRect(28, 492, 604, 20);
    subtitle.textColor = NSColor.secondaryLabelColor;
    [content addSubview:subtitle];

    [content addSubview:[self label:@"客户姓名" frame:NSMakeRect(28, 452, 120, 20)]];
    self.customerField = [[NSTextField alloc] initWithFrame:NSMakeRect(150, 446, 482, 28)];
    self.customerField.placeholderString = @"例如：张三";
    [content addSubview:self.customerField];

    [content addSubview:[self label:@"订单号（可选）" frame:NSMakeRect(28, 410, 120, 20)]];
    self.orderField = [[NSTextField alloc] initWithFrame:NSMakeRect(150, 404, 482, 28)];
    self.orderField.placeholderString = @"微信订单号或你的销售备注";
    [content addSubview:self.orderField];

    [content addSubview:[self label:@"客户设备码" frame:NSMakeRect(28, 368, 120, 20)]];
    self.deviceField = [[XHDeviceCodeField alloc] initWithFrame:NSMakeRect(150, 362, 350, 28)];
    self.deviceField.placeholderString = @"粘贴以 XHD- 开头的设备码";
    self.deviceField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    [content addSubview:self.deviceField];

    NSButton *pasteDeviceButton = [NSButton buttonWithTitle:@"读取剪贴板" target:self action:@selector(pasteDeviceCode:)];
    pasteDeviceButton.frame = NSMakeRect(510, 362, 122, 28);
    pasteDeviceButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:pasteDeviceButton];

    [content addSubview:[self label:@"付款日期" frame:NSMakeRect(28, 326, 120, 20)]];
    self.datePicker = [[NSDatePicker alloc] initWithFrame:NSMakeRect(150, 320, 180, 28)];
    self.datePicker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    self.datePicker.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    self.datePicker.dateValue = NSDate.date;
    [content addSubview:self.datePicker];

    NSButton *generateButton = [NSButton buttonWithTitle:@"生成并复制授权码" target:self action:@selector(generateLicense:)];
    generateButton.frame = NSMakeRect(432, 316, 200, 36);
    generateButton.bezelStyle = NSBezelStyleRounded;
    generateButton.keyEquivalent = @"\r";
    [content addSubview:generateButton];

    [content addSubview:[self label:@"生成结果" frame:NSMakeRect(28, 280, 120, 20)]];
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(28, 100, 604, 176)];
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSBezelBorder;
    self.licenseOutput = [[NSTextView alloc] initWithFrame:scrollView.bounds];
    self.licenseOutput.editable = NO;
    self.licenseOutput.selectable = YES;
    self.licenseOutput.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.licenseOutput.textContainerInset = NSMakeSize(8, 8);
    scrollView.documentView = self.licenseOutput;
    [content addSubview:scrollView];

    self.statusLabel = [NSTextField labelWithString:@"填写信息后生成，授权码会自动复制到剪贴板。"];
    self.statusLabel.frame = NSMakeRect(28, 66, 430, 20);
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    [content addSubview:self.statusLabel];

    NSButton *copyButton = [NSButton buttonWithTitle:@"复制" target:self action:@selector(copyLicense:)];
    copyButton.frame = NSMakeRect(474, 58, 72, 30);
    [content addSubview:copyButton];

    NSButton *recordsButton = [NSButton buttonWithTitle:@"授权记录" target:self action:@selector(openRecords:)];
    recordsButton.frame = NSMakeRect(550, 58, 82, 30);
    [content addSubview:recordsButton];

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showError:(NSString *)message {
    self.statusLabel.stringValue = message;
    self.statusLabel.textColor = NSColor.systemRedColor;
    NSBeep();
}

- (void)pasteDeviceCode:(id)sender {
    (void)sender;
    NSString *value = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
    if (!value.length) {
        [self showError:@"剪贴板没有可读取的文字，请先复制客户设备码。"];
        return;
    }
    self.deviceField.stringValue = value;
    self.statusLabel.stringValue = @"已从剪贴板读取设备码，请核对后生成授权码。";
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
}

- (NSData *)signatureForPayload:(NSData *)payload error:(NSString **)errorMessage {
    NSString *keyPath = self.privateKeyPath;
    if (![[NSFileManager defaultManager] isReadableFileAtPath:keyPath]) {
        if (errorMessage) *errorMessage = @"找不到授权签名密钥，请检查绣绘项目的 signing/activation 目录。";
        return nil;
    }

    NSString *temporaryDirectory = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[@"xiuhui-license-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSString *payloadPath = [temporaryDirectory stringByAppendingPathComponent:@"payload.json"];
    NSString *signaturePath = [temporaryDirectory stringByAppendingPathComponent:@"signature.bin"];
    NSError *fileError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:temporaryDirectory
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions : @0700}
                                                    error:&fileError];
    if (fileError || ![payload writeToFile:payloadPath options:NSDataWritingAtomic error:&fileError]) {
        if (errorMessage) *errorMessage = @"无法创建临时签名文件。";
        return nil;
    }

    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/openssl"];
    task.arguments = @[@"dgst", @"-sha256", @"-sign", keyPath, @"-out", signaturePath, payloadPath];
    NSPipe *errorPipe = [NSPipe pipe];
    task.standardError = errorPipe;
    NSError *launchError = nil;
    BOOL launched = [task launchAndReturnError:&launchError];
    if (launched) [task waitUntilExit];
    NSData *signature = launched && task.terminationStatus == 0
        ? [NSData dataWithContentsOfFile:signaturePath]
        : nil;
    if (!signature.length && errorMessage) {
        NSData *details = [errorPipe.fileHandleForReading readDataToEndOfFile];
        NSString *detailText = [[NSString alloc] initWithData:details encoding:NSUTF8StringEncoding];
        *errorMessage = detailText.length ? detailText : (launchError.localizedDescription ?: @"签名失败。");
    }
    [[NSFileManager defaultManager] removeItemAtPath:temporaryDirectory error:nil];
    return signature;
}

- (void)appendRecord:(NSDictionary *)payload deviceCode:(NSString *)deviceCode token:(NSString *)token {
    NSString *recordsPath = self.recordsPath;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:recordsPath];
    if (!exists) {
        NSString *header = @"签发时间,客户姓名,订单号,设备码,开始日期,到期日期,授权编号,授权码\n";
        [header writeToFile:recordsPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        chmod(recordsPath.fileSystemRepresentation, 0600);
    }
    NSArray<NSString *> *fields = @[
        XHCSVField([NSDate.date descriptionWithLocale:@"zh_CN"]),
        XHCSVField(payload[@"customer"]),
        XHCSVField(payload[@"order_reference"]),
        XHCSVField(deviceCode),
        XHCSVField(payload[@"starts_on"]),
        XHCSVField(payload[@"expires_on"]),
        XHCSVField(payload[@"license_id"]),
        XHCSVField(token),
    ];
    NSString *line = [[fields componentsJoinedByString:@","] stringByAppendingString:@"\n"];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:recordsPath];
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

- (void)generateLicense:(id)sender {
    (void)sender;
    NSString *customer = [self.customerField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!customer.length) {
        [self showError:@"请先填写客户姓名。"];
        return;
    }
    NSString *deviceID = XHNormalizeDeviceID(self.deviceField.stringValue);
    if (!deviceID.length) {
        [self showError:@"设备码格式不正确，请重新复制客户提供的 XHD- 设备码。"];
        return;
    }

    NSTimeZone *chinaTimeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = chinaTimeZone;
    NSDateComponents *dateParts = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
                                              fromDate:self.datePicker.dateValue];
    NSDate *startDate = [calendar dateFromComponents:dateParts];
    NSDate *expiryDate = [calendar dateByAddingUnit:NSCalendarUnitYear value:1 toDate:startDate options:0];
    NSDateFormatter *dayFormatter = [NSDateFormatter new];
    dayFormatter.calendar = calendar;
    dayFormatter.timeZone = chinaTimeZone;
    dayFormatter.dateFormat = @"yyyy-MM-dd";
    NSString *startsOn = [dayFormatter stringFromDate:startDate];
    NSString *expiresOn = [dayFormatter stringFromDate:expiryDate];

    NSDictionary *payload = @{
        @"app_id" : XHAppID,
        @"customer" : [customer substringToIndex:MIN(customer.length, (NSUInteger)120)],
        @"device_id" : deviceID,
        @"expires_at" : @((NSInteger)expiryDate.timeIntervalSince1970),
        @"expires_on" : expiresOn,
        @"issued_at" : @((NSInteger)NSDate.date.timeIntervalSince1970),
        @"lease_until" : @((NSInteger)expiryDate.timeIntervalSince1970),
        @"license_id" : NSUUID.UUID.UUIDString,
        @"offline" : @YES,
        @"order_reference" : [self.orderField.stringValue substringToIndex:MIN(self.orderField.stringValue.length, (NSUInteger)120)],
        @"starts_at" : @((NSInteger)startDate.timeIntervalSince1970),
        @"starts_on" : startsOn,
        @"version" : @(XHLicenseVersion),
    };
    NSError *jsonError = nil;
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingSortedKeys error:&jsonError];
    if (!payloadData) {
        [self showError:jsonError.localizedDescription ?: @"无法生成授权数据。"];
        return;
    }
    NSString *signingError = nil;
    NSData *signature = [self signatureForPayload:payloadData error:&signingError];
    if (!signature.length) {
        [self showError:signingError ?: @"授权签名失败。"];
        return;
    }

    NSString *token = [NSString stringWithFormat:@"%@.%@", XHBase64URL(payloadData), XHBase64URL(signature)];
    self.licenseOutput.string = token;
    [self copyLicense:nil];
    [self appendRecord:payload deviceCode:self.deviceField.stringValue token:token];
    self.statusLabel.stringValue = [NSString stringWithFormat:@"已生成并复制：%@ 至 %@，仅限该设备。", startsOn, expiresOn];
    self.statusLabel.textColor = NSColor.systemGreenColor;
}

- (void)copyLicense:(id)sender {
    (void)sender;
    if (!self.licenseOutput.string.length) return;
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:self.licenseOutput.string forType:NSPasteboardTypeString];
}

- (void)openRecords:(id)sender {
    (void)sender;
    NSString *recordsPath = self.recordsPath;
    if (![[NSFileManager defaultManager] fileExistsAtPath:recordsPath]) {
        NSString *header = @"签发时间,客户姓名,订单号,设备码,开始日期,到期日期,授权编号,授权码\n";
        [header writeToFile:recordsPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        chmod(recordsPath.fileSystemRepresentation, 0600);
    }
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:recordsPath]]];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        XHGeneratorDelegate *delegate = [XHGeneratorDelegate new];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }
    return 0;
}

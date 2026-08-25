#import "LKCoreDeviceTunnelDiscovery.h"

static NSTimeInterval const LKCoreDeviceTunnelCacheLifetime = 3.0;

static dispatch_queue_t LKCoreDeviceTunnelDiscoveryQueue;
static NSArray<LKCoreDeviceTunnel *> *LKCoreDeviceTunnelCache;
static NSTimeInterval LKCoreDeviceTunnelCacheTimestamp;

@interface LKCoreDeviceTunnel ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite) NSString *IPv6Address;

@end

@implementation LKCoreDeviceTunnel

- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                       IPv6Address:(NSString *)IPv6Address {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _name = [name copy];
        _IPv6Address = [IPv6Address copy];
    }
    return self;
}

@end

@interface LKCoreDeviceTunnelDiscovery ()

+ (NSArray<LKCoreDeviceTunnel *> *)connectedTunnels;
+ (nullable NSDictionary *)runDeviceControlWithArguments:(NSArray<NSString *> *)arguments JSONOutputURL:(NSURL *)JSONOutputURL;

@end

@implementation LKCoreDeviceTunnelDiscovery

+ (void)fetchConnectedTunnelsWithCompletion:(void (^)(NSArray<LKCoreDeviceTunnel *> *tunnels))completion {
    if (!completion) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        LKCoreDeviceTunnelDiscoveryQueue = dispatch_queue_create("com.lookinside.coredevice-discovery", DISPATCH_QUEUE_SERIAL);
    });

    dispatch_async(LKCoreDeviceTunnelDiscoveryQueue, ^{
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        NSArray<LKCoreDeviceTunnel *> *tunnels = LKCoreDeviceTunnelCache;
        if (!tunnels || now - LKCoreDeviceTunnelCacheTimestamp >= LKCoreDeviceTunnelCacheLifetime) {
            tunnels = [self connectedTunnels];
            LKCoreDeviceTunnelCache = tunnels;
            LKCoreDeviceTunnelCacheTimestamp = now;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(tunnels ?: @[]);
        });
    });
}

+ (NSArray<LKCoreDeviceTunnel *> *)connectedTunnels {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *temporaryDirectory = [[fileManager.temporaryDirectory URLByAppendingPathComponent:@"lookinside-coredevice" isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    NSError *directoryError = nil;
    if (![fileManager createDirectoryAtURL:temporaryDirectory withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
        return @[];
    }

    NSURL *listURL = [temporaryDirectory URLByAppendingPathComponent:@"devices.json"];
    NSDictionary *listResult = [self runDeviceControlWithArguments:@[
        @"devicectl", @"list", @"devices", @"--quiet", @"--timeout", @"5", @"--json-output", listURL.path
    ] JSONOutputURL:listURL];

    NSMutableArray<LKCoreDeviceTunnel *> *tunnels = [NSMutableArray array];
    NSArray *devices = [listResult[@"result"][@"devices"] isKindOfClass:NSArray.class] ? listResult[@"result"][@"devices"] : @[];
    for (NSDictionary *device in devices) {
        if (![device isKindOfClass:NSDictionary.class]) {
            continue;
        }

        NSDictionary *connectionProperties = [device[@"connectionProperties"] isKindOfClass:NSDictionary.class] ? device[@"connectionProperties"] : nil;
        NSDictionary *hardwareProperties = [device[@"hardwareProperties"] isKindOfClass:NSDictionary.class] ? device[@"hardwareProperties"] : nil;
        NSString *identifier = [device[@"identifier"] isKindOfClass:NSString.class] ? device[@"identifier"] : nil;
        if (![connectionProperties[@"tunnelState"] isEqualToString:@"connected"] ||
            ![hardwareProperties[@"reality"] isEqualToString:@"physical"] ||
            !identifier.length) {
            continue;
        }

        NSURL *detailsURL = [temporaryDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", identifier]];
        NSDictionary *detailsResult = [self runDeviceControlWithArguments:@[
            @"devicectl", @"device", @"info", @"details", @"--device", identifier, @"--quiet", @"--timeout", @"5", @"--json-output", detailsURL.path
        ] JSONOutputURL:detailsURL];
        NSDictionary *detailsConnection = [detailsResult[@"result"][@"connectionProperties"] isKindOfClass:NSDictionary.class] ? detailsResult[@"result"][@"connectionProperties"] : nil;
        NSString *IPv6Address = [detailsConnection[@"tunnelIPAddress"] isKindOfClass:NSString.class] ? detailsConnection[@"tunnelIPAddress"] : nil;
        if (![detailsConnection[@"tunnelState"] isEqualToString:@"connected"] || !IPv6Address.length) {
            continue;
        }

        NSDictionary *deviceProperties = [device[@"deviceProperties"] isKindOfClass:NSDictionary.class] ? device[@"deviceProperties"] : nil;
        NSString *name = [deviceProperties[@"name"] isKindOfClass:NSString.class] ? deviceProperties[@"name"] : identifier;
        [tunnels addObject:[[LKCoreDeviceTunnel alloc] initWithIdentifier:identifier name:name IPv6Address:IPv6Address]];
    }

    [fileManager removeItemAtURL:temporaryDirectory error:nil];
    return [tunnels sortedArrayUsingComparator:^NSComparisonResult(LKCoreDeviceTunnel *left, LKCoreDeviceTunnel *right) {
        return [left.identifier compare:right.identifier];
    }];
}

+ (NSDictionary *)runDeviceControlWithArguments:(NSArray<NSString *> *)arguments JSONOutputURL:(NSURL *)JSONOutputURL {
    if (![NSFileManager.defaultManager isExecutableFileAtPath:@"/usr/bin/xcrun"]) {
        return nil;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/xcrun"];
    task.arguments = arguments;
    NSFileHandle *nullDevice = [NSFileHandle fileHandleForWritingAtPath:@"/dev/null"];
    task.standardOutput = nullDevice;
    task.standardError = nullDevice;

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        return nil;
    }
    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        return nil;
    }

    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:JSONOutputURL options:0 error:&readError];
    if (!data.length) {
        return nil;
    }

    NSError *JSONError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&JSONError];
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

@end

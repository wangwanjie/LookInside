#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A physical device that is reachable through Xcode's CoreDevice developer
/// tunnel instead of the legacy usbmux socket.
@interface LKCoreDeviceTunnel : NSObject

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSString *IPv6Address;

- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                       IPv6Address:(NSString *)IPv6Address NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

/// Discovers physical devices with an active CoreDevice developer tunnel.
/// Results are delivered on the main queue and cached briefly because the
/// launch screen polls for inspectable apps frequently.
@interface LKCoreDeviceTunnelDiscovery : NSObject

+ (void)fetchConnectedTunnelsWithCompletion:(void (^)(NSArray<LKCoreDeviceTunnel *> *tunnels))completion;

@end

NS_ASSUME_NONNULL_END

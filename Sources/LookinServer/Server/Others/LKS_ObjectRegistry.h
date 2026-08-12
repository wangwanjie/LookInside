#if defined(SHOULD_COMPILE_LOOKIN_SERVER) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_VISION || TARGET_OS_MAC)
//
//  LKS_ObjectRegistry.h
//  LookinServer
//
//  Created by Li Kai on 2019/4/21.
//  https://lookin.work
//

#import <Foundation/Foundation.h>

@interface LKS_ObjectRegistry : NSObject

+ (instancetype)sharedInstance;

- (unsigned long)addObject:(NSObject *)object;

- (NSObject *)objectWithOid:(unsigned long)oid;

/// Starts replacing the retained objects associated with the latest hierarchy response.
- (void)beginHierarchySnapshot;

/// Stops collecting objects for the hierarchy currently being built.
- (void)endHierarchySnapshot;

/// Releases all objects retained for the current hierarchy.
- (void)discardHierarchySnapshot;

/// Keeps an object alive between the hierarchy response and its detail request.
- (void)retainObjectForCurrentHierarchySnapshot:(NSObject *)object oid:(unsigned long)oid;

/// Transfers requested objects to a detail handler and removes them from the snapshot.
- (NSDictionary<NSNumber *, NSObject *> *)consumeHierarchySnapshotObjectsWithOids:(NSArray<NSNumber *> *)oids;

@end

#endif /* SHOULD_COMPILE_LOOKIN_SERVER */

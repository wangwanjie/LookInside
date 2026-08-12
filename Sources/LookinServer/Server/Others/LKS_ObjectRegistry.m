#if defined(SHOULD_COMPILE_LOOKIN_SERVER) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_VISION || TARGET_OS_MAC)
//
//  LKS_ObjectRegistry.m
//  LookinServer
//
//  Created by Li Kai on 2019/4/21.
//  https://lookin.work
//

#import "LKS_ObjectRegistry.h"
#import <objc/runtime.h>

@interface LKS_ObjectRegistry ()

@property(nonatomic, strong) NSPointerArray *data;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSObject *> *hierarchySnapshotObjects;
@property(nonatomic, assign) BOOL collectingHierarchySnapshot;

@end

@implementation LKS_ObjectRegistry

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static LKS_ObjectRegistry *instance = nil;
    dispatch_once(&onceToken,^{
        instance = [[super allocWithZone:NULL] init];
    });
    return instance;
}

+ (id)allocWithZone:(struct _NSZone *)zone{
    return [self sharedInstance];
}

- (instancetype)init {
    if (self = [super init]) {
        self.data = [NSPointerArray weakObjectsPointerArray];
        // index 为 0 用 Null 填充
        self.data.count = 1;
        self.hierarchySnapshotObjects = [NSMutableDictionary dictionary];
    }
    return self;
}

- (unsigned long)addObject:(NSObject *)object {
    if (!object) {
        return 0;
    }
    [self.data addPointer:(void *)object];
    return self.data.count - 1;
}

- (NSObject *)objectWithOid:(unsigned long)oid {
    if (self.data.count <= oid) {
        return nil;
    }
    id object = [self.data pointerAtIndex:oid];
    return object;
}

- (void)beginHierarchySnapshot {
    [self.hierarchySnapshotObjects removeAllObjects];
    self.collectingHierarchySnapshot = YES;
}

- (void)endHierarchySnapshot {
    self.collectingHierarchySnapshot = NO;
}

- (void)discardHierarchySnapshot {
    self.collectingHierarchySnapshot = NO;
    [self.hierarchySnapshotObjects removeAllObjects];
}

- (void)retainObjectForCurrentHierarchySnapshot:(NSObject *)object oid:(unsigned long)oid {
    if (!self.collectingHierarchySnapshot || !object || oid == 0) {
        return;
    }
    self.hierarchySnapshotObjects[@(oid)] = object;
}

- (NSDictionary<NSNumber *, NSObject *> *)consumeHierarchySnapshotObjectsWithOids:(NSArray<NSNumber *> *)oids {
    NSMutableDictionary<NSNumber *, NSObject *> *objects = [NSMutableDictionary dictionary];
    for (NSNumber *oid in oids) {
        NSObject *object = self.hierarchySnapshotObjects[oid];
        if (object) {
            objects[oid] = object;
            [self.hierarchySnapshotObjects removeObjectForKey:oid];
        }
    }
    return objects.copy;
}

@end

#endif /* SHOULD_COMPILE_LOOKIN_SERVER */

#import <Foundation/Foundation.h>

#import "LKS_ObjectRegistry.h"

static void LKSFail(NSString *message) {
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    exit(EXIT_FAILURE);
}

__attribute__((noinline))
static void LKSExpectSnapshotObject(LKS_ObjectRegistry *registry, unsigned long oid) {
    if (![registry objectWithOid:oid]) {
        LKSFail(@"the current hierarchy snapshot did not retain its object");
    }
}

__attribute__((noinline))
static void LKSConsumeSnapshotObject(LKS_ObjectRegistry *registry, unsigned long oid) {
    NSDictionary<NSNumber *, NSObject *> *consumed =
        [registry consumeHierarchySnapshotObjectsWithOids:@[@(oid)]];
    if (!consumed[@(oid)]) {
        LKSFail(@"the detail request did not consume the retained snapshot object");
    }
}

static void LKSVerifyReplacingSnapshotReleasesUnconsumedObjects(LKS_ObjectRegistry *registry) {
    __weak NSObject *weakObject = nil;
    @autoreleasepool {
        NSObject *object = [NSObject new];
        weakObject = object;
        unsigned long oid = [registry addObject:object];
        [registry beginHierarchySnapshot];
        [registry retainObjectForCurrentHierarchySnapshot:object oid:oid];
        [registry endHierarchySnapshot];
        object = nil;
    }

    [registry beginHierarchySnapshot];
    [registry endHierarchySnapshot];
    if (weakObject) {
        LKSFail(@"replacing the hierarchy snapshot retained an object from the old hierarchy");
    }
}

int main(void) {
    @autoreleasepool {
        LKS_ObjectRegistry *registry = [LKS_ObjectRegistry sharedInstance];
        [registry beginHierarchySnapshot];

        __weak NSObject *weakObject = nil;
        unsigned long oid = 0;
        @autoreleasepool {
            NSObject *object = [NSObject new];
            weakObject = object;
            oid = [registry addObject:object];
            [registry retainObjectForCurrentHierarchySnapshot:object oid:oid];
            object = nil;
        }
        [registry endHierarchySnapshot];

        @autoreleasepool {
            LKSExpectSnapshotObject(registry, oid);
        }

        @autoreleasepool {
            LKSConsumeSnapshotObject(registry, oid);
        }

        if (weakObject) {
            LKSFail(@"the object stayed alive after the detail handler released it");
        }
        if ([registry objectWithOid:oid]) {
            LKSFail(@"the weak registry still resolved the released object");
        }

        LKSVerifyReplacingSnapshotReleasesUnconsumedObjects(registry);
        [registry discardHierarchySnapshot];
    }
    return EXIT_SUCCESS;
}

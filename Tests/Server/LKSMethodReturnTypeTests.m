#import <Foundation/Foundation.h>

#import "LKS_MethodReturnType.h"

@interface LKSMethodReturnTypeFixture : NSObject

- (id)objectValue;
- (Class)classValue;
- (double)doubleValue;
- (NSInteger)integerValue;
- (void *)pointerValue;
- (void)voidValue;

@end

@implementation LKSMethodReturnTypeFixture

- (id)objectValue {
    return self;
}

- (Class)classValue {
    return self.class;
}

- (double)doubleValue {
    return 1.0;
}

- (NSInteger)integerValue {
    return 1;
}

- (void *)pointerValue {
    return NULL;
}

- (void)voidValue {
}

@end

static void LKSExpectReturnType(LKSMethodReturnTypeFixture *fixture, SEL selector, BOOL expectedObject) {
    NSMethodSignature *signature = [fixture methodSignatureForSelector:selector];
    BOOL actualObject = LKSMethodSignatureReturnsObject(signature);
    if (actualObject != expectedObject) {
        fprintf(stderr,
                "FAIL: %s has return type %s and was classified as %s\n",
                sel_getName(selector),
                signature.methodReturnType,
                actualObject ? "object" : "non-object");
        exit(EXIT_FAILURE);
    }
}

static void LKSExpectEncodedReturnType(const char *types, BOOL expectedObject) {
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:types];
    BOOL actualObject = LKSMethodSignatureReturnsObject(signature);
    if (actualObject != expectedObject) {
        fprintf(stderr,
                "FAIL: encoded return type %s was classified as %s\n",
                signature.methodReturnType,
                actualObject ? "object" : "non-object");
        exit(EXIT_FAILURE);
    }
}

int main(void) {
    @autoreleasepool {
        LKSMethodReturnTypeFixture *fixture = [LKSMethodReturnTypeFixture new];
        LKSExpectReturnType(fixture, @selector(objectValue), YES);
        LKSExpectReturnType(fixture, @selector(classValue), YES);
        LKSExpectReturnType(fixture, @selector(doubleValue), NO);
        LKSExpectReturnType(fixture, @selector(integerValue), NO);
        LKSExpectReturnType(fixture, @selector(pointerValue), NO);
        LKSExpectReturnType(fixture, @selector(voidValue), NO);
        LKSExpectEncodedReturnType("r@@:", YES);
        LKSExpectEncodedReturnType("@?@:", YES);
        LKSExpectEncodedReturnType("r^v@:", NO);
    }
    return EXIT_SUCCESS;
}

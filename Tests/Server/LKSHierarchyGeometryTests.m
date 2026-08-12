#import <Foundation/Foundation.h>

#import "LKS_HierarchyGeometry.h"

static void LKSExpectRectValidity(CGRect rect, BOOL expectedValid, const char *name) {
    BOOL actualValid = LKSHierarchyRectIsValid(rect);
    if (actualValid != expectedValid) {
        fprintf(stderr, "FAIL: %s was classified as %s\n", name, actualValid ? "valid" : "invalid");
        exit(EXIT_FAILURE);
    }
}

int main(void) {
    @autoreleasepool {
        LKSExpectRectValidity(CGRectMake(0, 0, 414, 896), YES, "normal frame");
        LKSExpectRectValidity(CGRectZero, YES, "zero frame");
        LKSExpectRectValidity(CGRectMake(-DBL_MAX / 2, -DBL_MAX / 2, DBL_MAX, DBL_MAX), NO, "Lottie infinite frame");
        LKSExpectRectValidity(CGRectMake(NAN, 0, 10, 10), NO, "NaN frame");
        LKSExpectRectValidity(CGRectMake(INFINITY, 0, 10, 10), NO, "infinite origin");
        LKSExpectRectValidity(CGRectMake(0, 0, -1, 10), NO, "negative width");
        LKSExpectRectValidity(CGRectMake(100001, 0, 10, 10), NO, "unreasonable origin");
    }
    return EXIT_SUCCESS;
}

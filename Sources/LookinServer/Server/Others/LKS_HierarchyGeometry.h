#pragma once

#import <Foundation/Foundation.h>
#import <math.h>

NS_INLINE BOOL LKSHierarchyRectIsValid(CGRect rect) {
    if (CGRectIsNull(rect) || CGRectIsInfinite(rect)) {
        return NO;
    }

    const CGFloat values[] = {
        rect.origin.x,
        rect.origin.y,
        rect.size.width,
        rect.size.height,
    };
    for (NSUInteger index = 0; index < sizeof(values) / sizeof(values[0]); index++) {
        if (isnan(values[index]) || isinf(values[index])) {
            return NO;
        }
    }

    return fabs(rect.origin.x) <= 100000 &&
        fabs(rect.origin.y) <= 100000 &&
        rect.size.width >= 0 && rect.size.width <= 100000 &&
        rect.size.height >= 0 && rect.size.height <= 100000;
}

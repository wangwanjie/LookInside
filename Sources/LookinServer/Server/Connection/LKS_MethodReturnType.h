#import <Foundation/Foundation.h>

#include <string.h>

NS_ASSUME_NONNULL_BEGIN

static inline BOOL LKSMethodSignatureReturnsObject(NSMethodSignature *signature) {
    const char *returnType = signature.methodReturnType;
    while (*returnType != '\0' && strchr("rnNoORV", *returnType) != NULL) {
        returnType++;
    }
    return *returnType == '@' || *returnType == '#';
}

NS_ASSUME_NONNULL_END

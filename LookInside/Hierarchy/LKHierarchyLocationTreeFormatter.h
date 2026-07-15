//
//  LKHierarchyLocationTreeFormatter.h
//  Lookin
//
//  Created by OpenAI on 2026/7/15.
//

#import <Foundation/Foundation.h>

@class LookinDisplayItem;

NS_ASSUME_NONNULL_BEGIN

@interface LKHierarchyLocationTreeFormatter : NSObject

+ (NSString *)locationTreeForDisplayItem:(LookinDisplayItem *)displayItem
                           titleProvider:(NSString * _Nullable (^)(LookinDisplayItem *item))titleProvider
                        subtitleProvider:(NSString * _Nullable (^)(LookinDisplayItem *item))subtitleProvider;

@end

NS_ASSUME_NONNULL_END

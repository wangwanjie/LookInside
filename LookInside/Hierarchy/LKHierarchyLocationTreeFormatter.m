//
//  LKHierarchyLocationTreeFormatter.m
//  Lookin
//
//  Created by OpenAI on 2026/7/15.
//

#import "LKHierarchyLocationTreeFormatter.h"
#import "LookinDisplayItem.h"

@implementation LKHierarchyLocationTreeFormatter

+ (NSString *)locationTreeForDisplayItem:(LookinDisplayItem *)displayItem
                           titleProvider:(NSString * _Nullable (^)(LookinDisplayItem *item))titleProvider
                        subtitleProvider:(NSString * _Nullable (^)(LookinDisplayItem *item))subtitleProvider {
    if (!displayItem) {
        return @"";
    }
    
    NSMutableArray<LookinDisplayItem *> *items = [NSMutableArray array];
    LookinDisplayItem *cursor = displayItem;
    while (cursor) {
        [items insertObject:cursor atIndex:0];
        cursor = cursor.superItem;
    }
    
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:items.count];
    [items enumerateObjectsUsingBlock:^(LookinDisplayItem * _Nonnull item, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *indent = [@"" stringByPaddingToLength:idx * 3 withString:@" " startingAtIndex:0];
        NSString *title = titleProvider ? titleProvider(item) : nil;
        if (title.length == 0) {
            title = item.customDisplayTitle.length ? item.customDisplayTitle : @"<Unknown>";
        }
        NSString *subtitle = subtitleProvider ? subtitleProvider(item) : nil;
        NSString *frame = [self _stringFromFrame:item.frame];
        
        NSMutableArray<NSString *> *components = [NSMutableArray arrayWithObject:title];
        if (subtitle.length) {
            [components addObject:subtitle];
        }
        [components addObject:[NSString stringWithFormat:@"frame=%@", frame]];
        
        [lines addObject:[NSString stringWithFormat:@"%@└─ %@", indent, [components componentsJoinedByString:@" "]]];
    }];
    
    return [lines componentsJoinedByString:@"\n"];
}

+ (NSString *)_stringFromFrame:(CGRect)frame {
    return [NSString stringWithFormat:@"(%@, %@, %@, %@)",
            [self _stringFromCGFloat:frame.origin.x],
            [self _stringFromCGFloat:frame.origin.y],
            [self _stringFromCGFloat:frame.size.width],
            [self _stringFromCGFloat:frame.size.height]];
}

+ (NSString *)_stringFromCGFloat:(CGFloat)value {
    NSString *string = [NSString stringWithFormat:@"%.3f", value];
    while ([string containsString:@"."] && [string hasSuffix:@"0"]) {
        string = [string substringToIndex:string.length - 1];
    }
    if ([string hasSuffix:@"."]) {
        string = [string substringToIndex:string.length - 1];
    }
    return string;
}

@end

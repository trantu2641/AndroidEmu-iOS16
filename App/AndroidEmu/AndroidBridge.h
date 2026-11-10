#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^AndroidStateCallback)(NSString *state);

@interface AndroidBridge : NSObject

+ (instancetype)shared;

- (void)startWithDisplay:(nullable UIView *)display
                callback:(AndroidStateCallback)callback;

- (void)stop;

- (void)touchWithAction:(int)action
                      x:(float)x
                      y:(float)y;

@end

NS_ASSUME_NONNULL_END

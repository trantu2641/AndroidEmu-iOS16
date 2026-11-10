#import "AndroidBridge.h"

@interface AndroidBridge ()

@property(nonatomic, assign) BOOL running;
@property(nonatomic, copy) AndroidStateCallback callback;
@property(nonatomic, weak) UIView *display;

@end

@implementation AndroidBridge

+ (instancetype)shared {

    static AndroidBridge *instance;

    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        instance = [[AndroidBridge alloc] init];
    });

    return instance;
}

- (void)startWithDisplay:(UIView *)display
                callback:(AndroidStateCallback)callback {

    if (self.running) {
        return;
    }

    self.running = YES;
    self.display = display;
    self.callback = callback;

    [self report:@"Initializing Android runtime..."];

    dispatch_async(
        dispatch_get_global_queue(
            QOS_CLASS_USER_INITIATED,
            0
        ),
        ^{

            [self report:@"Loading Kernarium..."];

            /*
             ------------------------------------------------
             KERNARIUM ENTRY POINT
             ------------------------------------------------

             Chỗ này sẽ được nối với KernariumRuntime
             sau khi framework được build.

             Ví dụ:

             kernarium_runtime_start(...)

             */

            [NSThread sleepForTimeInterval:0.2];

            [self report:@"Android kernel starting..."];

            [NSThread sleepForTimeInterval:0.2];

            [self report:@"Android userspace starting..."];

            [NSThread sleepForTimeInterval:0.2];

            [self report:@"Starting SurfaceFlinger..."];

            [NSThread sleepForTimeInterval:0.2];

            [self report:@"Android ready"];
        }
    );
}

- (void)stop {

    if (!self.running) {
        return;
    }

    self.running = NO;

    /*
     kernarium_runtime_stop();
    */
}

- (void)touchWithAction:(int)action
                      x:(float)x
                      y:(float)y {

    if (!self.running) {
        return;
    }

    /*
     Sẽ chuyển sang Android input device:

     EV_ABS
     EV_KEY
     EV_SYN

     hoặc input bridge của Kernarium.
    */

    NSLog(
        @"[AndroidEmu] touch action=%d x=%f y=%f",
        action,
        x,
        y
    );
}

- (void)report:(NSString *)message {

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (self.callback) {
                self.callback(message);
            }

            NSLog(
                @"[AndroidEmu] %@",
                message
            );
        }
    );
}

@end

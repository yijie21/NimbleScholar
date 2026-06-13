#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, WKNavigationDelegate>
@property NSWindow *window;
@property WKWebView *webView;
@property NSTask *serverTask;
@property NSString *port;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.port = [[[NSProcessInfo processInfo] environment] objectForKey:@"PAPER_APP_PORT"] ?: @"8765";
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self buildMenu];
    [self buildWindow];
    [self startServerIfNeeded];
    [self waitForServerAndLoad];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    if (self.serverTask && self.serverTask.isRunning) {
        [self.serverTask terminate];
    }
}

- (void)buildMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [menu addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@""];
    [appMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Quit Nimble Scholar" action:@selector(terminate:) keyEquivalent:@"q"]];
    [appItem setSubmenu:appMenu];
    [NSApp setMainMenu:menu];
}

- (void)buildWindow {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:config];
    self.webView.navigationDelegate = self;

    self.window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1260, 820)
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered
        defer:NO];
    self.window.title = @"Nimble Scholar";
    self.window.titlebarAppearsTransparent = NO;
    if (@available(macOS 11.0, *)) {
        self.window.toolbarStyle = NSWindowToolbarStyleAutomatic;
    }
    self.window.contentView = self.webView;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (NSString *)baseURLString {
    return [NSString stringWithFormat:@"http://127.0.0.1:%@", self.port];
}

- (BOOL)isServerRunning {
    NSURL *url = [NSURL URLWithString:[[self baseURLString] stringByAppendingString:@"/api/papers"]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 0.35;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block BOOL ok = NO;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                ok = ((NSHTTPURLResponse *)response).statusCode == 200;
            }
            dispatch_semaphore_signal(sema);
        }];
    [task resume];
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)));
    return ok;
}

- (NSURL *)serverScriptURL {
    return [[NSBundle mainBundle].resourceURL URLByAppendingPathComponent:@"app/server.py"];
}

- (void)startServerIfNeeded {
    if ([self isServerRunning]) {
        return;
    }

    NSString *dataPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"PAPER_APP_DATA_DIR"];
    NSURL *dataURL = dataPath.length > 0
        ? [NSURL fileURLWithPath:dataPath]
        : [[[NSFileManager defaultManager] homeDirectoryForCurrentUser]
            URLByAppendingPathComponent:@"Library/Application Support/Nimble Scholar"];
    [self seedDataDirectory:dataURL];
    NSURL *logDir = [[[NSFileManager defaultManager] homeDirectoryForCurrentUser]
        URLByAppendingPathComponent:@"Library/Logs/Nimble Scholar"];
    [[NSFileManager defaultManager] createDirectoryAtURL:logDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *logURL = [logDir URLByAppendingPathComponent:@"nimble-scholar.log"];
    [[NSFileManager defaultManager] createFileAtPath:logURL.path contents:nil attributes:nil];
    NSFileHandle *logHandle = [NSFileHandle fileHandleForWritingAtPath:logURL.path];
    [logHandle seekToEndOfFile];

    self.serverTask = [[NSTask alloc] init];
    self.serverTask.executableURL = [NSURL fileURLWithPath:@"/usr/bin/python3"];
    self.serverTask.arguments = @[self.serverScriptURL.path];
    self.serverTask.currentDirectoryURL = [self.serverScriptURL URLByDeletingLastPathComponent];
    self.serverTask.environment = @{
        @"PORT": self.port,
        @"PAPER_APP_DATA_DIR": dataURL.path
    };
    self.serverTask.standardOutput = logHandle;
    self.serverTask.standardError = logHandle;

    NSError *error = nil;
    if (![self.serverTask launchAndReturnError:&error]) {
        [self showError:@"Nimble Scholar could not start the local server."];
    }
}

- (void)seedDataDirectory:(NSURL *)dataURL {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtURL:dataURL withIntermediateDirectories:YES attributes:nil error:nil];

    NSURL *targetDB = [dataURL URLByAppendingPathComponent:@"paper_app.sqlite3"];
    NSURL *seedDB = [[NSBundle mainBundle].resourceURL URLByAppendingPathComponent:@"seed/paper_app.sqlite3"];
    if (![fm fileExistsAtPath:targetDB.path] && [fm fileExistsAtPath:seedDB.path]) {
        [fm copyItemAtURL:seedDB toURL:targetDB error:nil];
    }

    NSURL *targetStorage = [dataURL URLByAppendingPathComponent:@"storage"];
    NSURL *seedStorage = [[NSBundle mainBundle].resourceURL URLByAppendingPathComponent:@"seed/storage"];
    if (![fm fileExistsAtPath:targetStorage.path] && [fm fileExistsAtPath:seedStorage.path]) {
        [fm copyItemAtURL:seedStorage toURL:targetStorage error:nil];
    }
}

- (void)waitForServerAndLoad {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        for (int i = 0; i < 60; i++) {
            if ([self isServerRunning]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSURL *url = [NSURL URLWithString:[self baseURLString]];
                    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
                });
                return;
            }
            [NSThread sleepForTimeInterval:0.2];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showError:@"Nimble Scholar did not start in time."];
        });
    });
}

- (void)showError:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = @"Check ~/Library/Logs/Nimble Scholar/nimble-scholar.log.";
    alert.alertStyle = NSAlertStyleWarning;
    [alert runModal];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}

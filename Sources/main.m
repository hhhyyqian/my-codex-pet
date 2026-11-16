#import <AppKit/AppKit.h>

static NSString *const AgentLabel = @"com.huang.codexpet";

@interface TaskSnapshot : NSObject
@property NSString *taskID;
@property NSString *title;
@property NSString *source;
@property BOOL running;
@property NSDate *changedAt;
@end
@implementation TaskSnapshot @end

@interface SessionRecord : NSObject
@property NSString *taskID;
@property NSString *originator;
@property unsigned long long offset;
@property BOOL running;
@property NSDate *changedAt;
@end
@implementation SessionRecord
- (instancetype)init { if ((self = [super init])) { _taskID = @""; _originator = @""; _changedAt = NSDate.distantPast; } return self; }
@end

@interface CodexMonitor : NSObject
@property NSURL *sessionsURL;
@property NSURL *indexURL;
@property NSMutableDictionary<NSString *, SessionRecord *> *records;
- (NSArray<TaskSnapshot *> *)scan;
@end

@implementation CodexMonitor
- (instancetype)init {
    if ((self = [super init])) {
        NSURL *home = NSFileManager.defaultManager.homeDirectoryForCurrentUser;
        _sessionsURL = [home URLByAppendingPathComponent:@".codex/sessions" isDirectory:YES];
        _indexURL = [home URLByAppendingPathComponent:@".codex/session_index.jsonl"];
        _records = NSMutableDictionary.dictionary;
    }
    return self;
}

- (NSDictionary<NSString *, NSString *> *)loadTitles {
    NSString *text = [NSString stringWithContentsOfURL:self.indexURL encoding:NSUTF8StringEncoding error:nil];
    NSMutableDictionary *titles = NSMutableDictionary.dictionary;
    [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if ([json[@"id"] isKindOfClass:NSString.class] && [json[@"thread_name"] isKindOfClass:NSString.class]) {
            titles[json[@"id"]] = json[@"thread_name"];
        }
    }];
    return titles;
}

- (NSDate *)dateFromString:(NSString *)value {
    if (![value isKindOfClass:NSString.class]) return NSDate.date;
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ formatter = NSISO8601DateFormatter.new; formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds; });
    return [formatter dateFromString:value] ?: NSDate.date;
}

- (void)updateURL:(NSURL *)url {
    NSString *key = url.path;
    SessionRecord *record = self.records[key] ?: SessionRecord.new;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
    if (!handle) return;
    unsigned long long size = [handle seekToEndOfFile];
    if (size < record.offset) record = SessionRecord.new;
    if (size == record.offset) { [handle closeFile]; return; }
    [handle seekToFileOffset:record.offset];
    NSData *data = [handle readDataToEndOfFile];
    record.offset = size;
    [handle closeFile];

    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        NSDictionary *payload = [json[@"payload"] isKindOfClass:NSDictionary.class] ? json[@"payload"] : nil;
        if (!payload) return;
        NSDate *timestamp = [self dateFromString:json[@"timestamp"]];
        if ([json[@"type"] isEqual:@"session_meta"]) {
            NSString *taskID = payload[@"id"] ?: payload[@"session_id"];
            if ([taskID isKindOfClass:NSString.class]) record.taskID = taskID;
            if ([payload[@"originator"] isKindOfClass:NSString.class]) record.originator = payload[@"originator"];
        } else if ([json[@"type"] isEqual:@"event_msg"]) {
            NSString *event = payload[@"type"];
            if ([event isEqual:@"task_started"]) {
                record.running = YES; record.changedAt = timestamp;
            } else if ([event isEqual:@"task_complete"] || [event isEqual:@"turn_aborted"]) {
                record.running = NO; record.changedAt = timestamp;
            }
        }
    }];
    self.records[key] = record;
}

- (NSArray<TaskSnapshot *> *)scan {
    NSDictionary *titles = self.loadTitles;
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-7 * 24 * 60 * 60];
    NSArray *keys = @[NSURLIsRegularFileKey, NSURLContentModificationDateKey];
    NSDirectoryEnumerator *walker = [NSFileManager.defaultManager enumeratorAtURL:self.sessionsURL includingPropertiesForKeys:keys options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    for (NSURL *url in walker) {
        if (![url.pathExtension isEqual:@"jsonl"]) continue;
        NSDictionary *values = [url resourceValuesForKeys:keys error:nil];
        if (![values[NSURLIsRegularFileKey] boolValue] || [values[NSURLContentModificationDateKey] compare:cutoff] == NSOrderedAscending) continue;
        [self updateURL:url];
    }

    NSMutableArray *tasks = NSMutableArray.array;
    for (SessionRecord *record in self.records.allValues) {
        if (!record.taskID.length || [record.changedAt compare:cutoff] == NSOrderedAscending) continue;
        TaskSnapshot *task = TaskSnapshot.new;
        task.taskID = record.taskID;
        task.title = titles[record.taskID] ?: @"Codex 任务";
        task.source = [record.originator localizedCaseInsensitiveContainsString:@"desktop"] ? @"Codex Desktop" : @"VS Code";
        task.running = record.running;
        task.changedAt = record.changedAt;
        [tasks addObject:task];
    }
    [tasks sortUsingComparator:^NSComparisonResult(TaskSnapshot *a, TaskSnapshot *b) {
        if (a.running != b.running) return a.running ? NSOrderedAscending : NSOrderedDescending;
        return [b.changedAt compare:a.changedAt];
    }];
    return tasks;
}
@end

@protocol PetMenuProvider <NSObject>
- (NSMenu *)makeMenu;
- (void)setPanelExpanded:(BOOL)expanded;
@end

@interface PetView : NSView
@property (nonatomic) NSArray<TaskSnapshot *> *tasks;
@property (nonatomic) BOOL celebrating;
@property (nonatomic) BOOL cardOnly;
@property NSInteger frameIndex;
@property NSTrackingArea *hoverTrackingArea;
@property NSArray<NSImage *> *idleFrames;
@property NSArray<NSImage *> *workFrames;
@end

@implementation PetView
- (BOOL)isFlipped { return YES; }
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _tasks = @[];
        NSBundle *bundle=NSBundle.mainBundle;
        NSMutableArray *idle=NSMutableArray.array, *work=NSMutableArray.array;
        for (NSInteger i=1;i<=6;i++) {
            [idle addObject:[[NSImage alloc] initWithContentsOfURL:[bundle URLForResource:[NSString stringWithFormat:@"idle-%ld",i] withExtension:@"png"]]];
            [work addObject:[[NSImage alloc] initWithContentsOfURL:[bundle URLForResource:[NSString stringWithFormat:@"typing-%ld",i] withExtension:@"png"]]];
        }
        _idleFrames=idle; _workFrames=work;
        self.accessibilityLabel = @"Codex 任务悬浮宠物";
        [NSTimer scheduledTimerWithTimeInterval:.06 repeats:YES block:^(NSTimer *timer) { self.frameIndex++; self.needsDisplay = YES; }];
    }
    return self;
}
- (void)setTasks:(NSArray<TaskSnapshot *> *)tasks { _tasks = tasks; self.needsDisplay = YES; }
- (void)setCelebrating:(BOOL)value { _celebrating = value; self.needsDisplay = YES; }

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.hoverTrackingArea) [self removeTrackingArea:self.hoverTrackingArea];
    if (self.cardOnly) return;
    self.hoverTrackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways owner:self userInfo:nil];
    [self addTrackingArea:self.hoverTrackingArea];
}
- (void)mouseEntered:(NSEvent *)event {
    [(id<PetMenuProvider>)NSApp.delegate setPanelExpanded:YES];
}
- (void)mouseExited:(NSEvent *)event {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, .15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (NSPointInRect(self.window.mouseLocationOutsideOfEventStream, self.bounds)) return;
        [(id<PetMenuProvider>)NSApp.delegate setPanelExpanded:NO];
    });
}

- (void)text:(NSString *)text x:(CGFloat)x y:(CGFloat)y width:(CGFloat)width size:(CGFloat)size color:(NSColor *)color bold:(BOOL)bold {
    NSMutableParagraphStyle *style = NSMutableParagraphStyle.new; style.lineBreakMode = NSLineBreakByTruncatingTail;
    [text drawInRect:NSMakeRect(x, y, width, size + 7) withAttributes:@{NSFontAttributeName: bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size], NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: style}];
}
- (void)ellipse:(NSRect)rect color:(NSColor *)color { [color setFill]; [[NSBezierPath bezierPathWithOvalInRect:rect] fill]; }
- (void)drawRect:(NSRect)dirtyRect {
    BOOL running = NO; for (TaskSnapshot *task in self.tasks) if (task.running) { running = YES; break; }
    if (self.cardOnly) [self drawCardRunning:running]; else [self drawSamoyedRunning:running];
}

- (void)drawCheckAt:(NSPoint)point {
    [self ellipse:NSMakeRect(point.x, point.y, 16, 16) color:[NSColor colorWithRed:.12 green:.82 blue:.42 alpha:1]];
    NSBezierPath *check = NSBezierPath.new; [check moveToPoint:NSMakePoint(point.x+4,point.y+8)]; [check lineToPoint:NSMakePoint(point.x+7,point.y+11)]; [check lineToPoint:NSMakePoint(point.x+13,point.y+5)]; check.lineWidth=2; check.lineCapStyle=NSLineCapStyleRound; [NSColor.whiteColor setStroke]; [check stroke];
}

- (void)drawCardRunning:(BOOL)running {
    NSBezierPath *card = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(6, 6, self.bounds.size.width - 12, 116) xRadius:17 yRadius:17];
    NSColor *base = running ? [NSColor colorWithRed:.08 green:.12 blue:.18 alpha:.96] : [NSColor colorWithRed:.11 green:.10 blue:.19 alpha:.96];
    [base setFill]; [card fill]; [[NSColor colorWithWhite:1 alpha:.12] setStroke]; card.lineWidth = 1; [card stroke];
    NSString *status = running ? @"●  正在执行" : (self.celebrating ? @"✓  任务完成！" : @"☾  当前空闲");
    NSColor *accent = running ? [NSColor colorWithRed:.25 green:.95 blue:.66 alpha:1] : [NSColor colorWithRed:.64 green:.55 blue:1 alpha:1];
    [self text:status x:21 y:19 width:285 size:14 color:accent bold:YES];
    NSMutableArray *visible = NSMutableArray.array;
    for (TaskSnapshot *task in self.tasks) if (task.running == running && visible.count < (running ? 2 : 1)) [visible addObject:task];
    if (!visible.count) [self text:@"还没有发现 Codex 任务" x:21 y:52 width:290 size:12 color:[NSColor colorWithWhite:1 alpha:.72] bold:NO];
    for (NSInteger i = 0; i < visible.count; i++) {
        TaskSnapshot *task = visible[i]; CGFloat y = 51 + i * 28;
        if (!running) [self drawCheckAt:NSMakePoint(21,y-1)];
        NSString *prefix = running ? task.source : [NSString stringWithFormat:@"%@ · 已完成", task.source];
        CGFloat prefixX = running ? 21 : 43;
        [self text:prefix x:prefixX y:y width:105 size:10.5 color:running?[NSColor colorWithWhite:1 alpha:.55]:[NSColor colorWithRed:.3 green:1 blue:.59 alpha:.9] bold:!running];
        [self text:task.title x:132 y:y - 1 width:MAX(80,self.bounds.size.width-147) size:11.5 color:NSColor.whiteColor bold:NO];
    }
}

- (void)drawSamoyedRunning:(BOOL)running {
    NSArray<NSImage *> *frames=running?self.workFrames:self.idleFrames; NSInteger hold=running?3:4; NSImage *frame=frames[(self.frameIndex/hold)%frames.count];
    CGFloat side=136, y=self.bounds.size.height-side; NSRect target=NSMakeRect(NSMidX(self.bounds)-side/2,y,side,side);
    [frame drawInRect:target fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:@{NSImageHintInterpolation:@(NSImageInterpolationHigh)}];
    if (self.celebrating) for (NSInteger i=0;i<6;i++) { CGFloat a=i*M_PI/3+(self.frameIndex%5)*.12; [self text:@"✦" x:NSMidX(self.bounds)+cos(a)*68 y:y+55+sin(a)*45 width:16 size:13 color:@[NSColor.systemYellowColor,NSColor.systemPinkColor,NSColor.systemCyanColor][i%3] bold:NO]; }
}

- (void)mouseDragged:(NSEvent *)event { [(id<PetMenuProvider>)NSApp.delegate setPanelExpanded:NO]; [self.window performWindowDragWithEvent:event]; }
- (void)rightMouseDown:(NSEvent *)event {
    id<PetMenuProvider> delegate = (id<PetMenuProvider>)NSApp.delegate;
    if ([delegate respondsToSelector:@selector(makeMenu)]) [NSMenu popUpContextMenu:[delegate makeMenu] withEvent:event forView:self];
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, PetMenuProvider>
@property CodexMonitor *monitor;
@property NSPanel *panel;
@property NSPanel *infoPanel;
@property PetView *petView;
@property PetView *cardView;
@property NSStatusItem *statusItem;
@property NSSet<NSString *> *previousIDs;
@property BOOL firstScan;
@property BOOL scanning;
@property NSInteger runningCount;
- (NSMenu *)makeMenu;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory]; self.monitor = CodexMonitor.new; self.previousIDs = NSSet.set; self.firstScan = YES;
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"showMenuBar":@YES}];
    NSSize size = NSMakeSize(170,140); NSRect screen = NSScreen.mainScreen.visibleFrame; NSPoint origin = NSMakePoint(NSMaxX(screen)-size.width-24, NSMinY(screen)+42);
    self.panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(origin.x,origin.y,size.width,size.height) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    self.panel.opaque = NO; self.panel.backgroundColor = NSColor.clearColor; self.panel.hasShadow = NO; self.panel.level = NSFloatingWindowLevel; self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorStationary; self.panel.hidesOnDeactivate = NO;
    self.petView = [[PetView alloc] initWithFrame:NSMakeRect(0,0,size.width,size.height)]; self.panel.contentView = self.petView; [self.panel orderFrontRegardless];
    self.infoPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,330,128) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    self.infoPanel.opaque=NO; self.infoPanel.backgroundColor=NSColor.clearColor; self.infoPanel.hasShadow=YES; self.infoPanel.level=NSFloatingWindowLevel; self.infoPanel.collectionBehavior=self.panel.collectionBehavior; self.infoPanel.hidesOnDeactivate=NO;
    self.cardView=[[PetView alloc] initWithFrame:NSMakeRect(0,0,330,128)]; self.cardView.cardOnly=YES; self.infoPanel.contentView=self.cardView;
    [self syncStatusItem];
    [self refresh]; [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}
- (void)setPanelExpanded:(BOOL)expanded {
    if (!expanded || !self.panel.visible) { [self.infoPanel orderOut:nil]; return; }
    NSRect pet=self.panel.frame;
    NSScreen *best=NSScreen.mainScreen; CGFloat bestArea=0;
    for(NSScreen *screen in NSScreen.screens){NSRect intersection=NSIntersectionRect(pet,screen.visibleFrame);CGFloat area=intersection.size.width*intersection.size.height;if(area>bestArea){best=screen;bestArea=area;}}
    NSRect visible=NSInsetRect(best.visibleFrame,8,8); CGFloat gap=8, height=128, width=MIN(330,visible.size.width);
    CGFloat x=MIN(MAX(NSMidX(pet)-width/2,NSMinX(visible)),NSMaxX(visible)-width), y;
    if (NSMaxY(pet)+gap+height<=NSMaxY(visible)) y=NSMaxY(pet)+gap;
    else if (NSMinY(pet)-gap-height>=NSMinY(visible)) y=NSMinY(pet)-gap-height;
    else y=MIN(MAX(NSMidY(pet)-height/2,NSMinY(visible)),NSMaxY(visible)-height);
    NSRect frame=NSMakeRect(x,y,width,height); [self.infoPanel setFrame:frame display:YES]; self.cardView.frame=NSMakeRect(0,0,width,height); [self.infoPanel orderFrontRegardless];
}
- (void)syncStatusItem {
    BOOL visible=[NSUserDefaults.standardUserDefaults boolForKey:@"showMenuBar"];
    if (!visible && self.statusItem) { [NSStatusBar.systemStatusBar removeStatusItem:self.statusItem]; self.statusItem=nil; return; }
    if (visible && !self.statusItem) self.statusItem=[NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    if (self.statusItem) { self.statusItem.button.title=self.runningCount?[NSString stringWithFormat:@"🐶 %ld",self.runningCount]:@"🐶"; self.statusItem.button.toolTip=@"Codex Pet"; self.statusItem.menu=self.makeMenu; }
}
- (void)refresh {
    if (self.scanning) return; self.scanning = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{ NSArray *tasks = [self.monitor scan]; dispatch_async(dispatch_get_main_queue(), ^{
        self.petView.tasks = tasks; self.cardView.tasks=tasks; NSMutableSet *current = NSMutableSet.set; for (TaskSnapshot *task in tasks) if (task.running) [current addObject:task.taskID];
        if (!self.firstScan && self.previousIDs.count && !current.count) [self celebrate]; self.firstScan = NO; self.previousIDs = current.copy;
        self.runningCount=current.count; [self syncStatusItem]; self.scanning = NO;
    }); });
}
- (void)celebrate { self.petView.celebrating = YES; self.cardView.celebrating=YES; [self.panel orderFrontRegardless]; [[NSSound soundNamed:@"Glass"] play]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW,6*NSEC_PER_SEC),dispatch_get_main_queue(),^{ self.petView.celebrating=NO; self.cardView.celebrating=NO; }); }
- (NSURL *)agentURL { return [NSFileManager.defaultManager.homeDirectoryForCurrentUser URLByAppendingPathComponent:[@"Library/LaunchAgents" stringByAppendingPathComponent:[AgentLabel stringByAppendingString:@".plist"]]]; }
- (BOOL)launchEnabled { return [NSFileManager.defaultManager fileExistsAtPath:self.agentURL.path]; }
- (void)launchctl:(NSArray *)args { NSTask *task = NSTask.new; task.launchPath = @"/bin/launchctl"; task.arguments = args; [task launch]; [task waitUntilExit]; }
- (NSMenu *)makeMenu {
    NSMenu *menu = NSMenu.new; NSMenuItem *visible = [[NSMenuItem alloc] initWithTitle:self.panel.visible?@"隐藏宠物":@"显示宠物" action:@selector(toggleVisible:) keyEquivalent:@""]; visible.target=self; [menu addItem:visible];
    NSMenuItem *login = [[NSMenuItem alloc] initWithTitle:@"开机自启" action:@selector(toggleLaunch:) keyEquivalent:@""]; login.target=self; login.state=self.launchEnabled?NSControlStateValueOn:NSControlStateValueOff; [menu addItem:login]; [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *menuBar = [[NSMenuItem alloc] initWithTitle:@"在菜单栏显示" action:@selector(toggleMenuBar:) keyEquivalent:@""]; menuBar.target=self; menuBar.state=[NSUserDefaults.standardUserDefaults boolForKey:@"showMenuBar"]?NSControlStateValueOn:NSControlStateValueOff; [menu addItem:menuBar];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出 Codex Pet" action:@selector(quit:) keyEquivalent:@"q"]; quit.target=self; [menu addItem:quit]; return menu;
}
- (void)toggleVisible:(id)sender { if (self.panel.visible) { [self.infoPanel orderOut:nil]; [self.panel orderOut:nil]; } else [self.panel orderFrontRegardless]; if(self.statusItem)self.statusItem.menu=self.makeMenu; }
- (void)toggleMenuBar:(id)sender { BOOL next=![NSUserDefaults.standardUserDefaults boolForKey:@"showMenuBar"]; [NSUserDefaults.standardUserDefaults setBool:next forKey:@"showMenuBar"]; dispatch_async(dispatch_get_main_queue(),^{ [self syncStatusItem]; }); }
- (void)toggleLaunch:(id)sender {
    NSString *domain=[NSString stringWithFormat:@"gui/%d",getuid()];
    if (self.launchEnabled) { [self launchctl:@[@"bootout",domain,self.agentURL.path]]; [NSFileManager.defaultManager removeItemAtURL:self.agentURL error:nil]; }
    else { NSDictionary *plist=@{@"Label":AgentLabel,@"ProgramArguments":@[@"/usr/bin/open",@"-a",NSBundle.mainBundle.bundlePath],@"RunAtLoad":@YES}; [NSFileManager.defaultManager createDirectoryAtURL:self.agentURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil]; [plist writeToURL:self.agentURL atomically:YES]; [self launchctl:@[@"bootstrap",domain,self.agentURL.path]]; }
    if(self.statusItem)self.statusItem.menu=self.makeMenu;
}
- (void)quit:(id)sender { [NSApp terminate:nil]; }
@end

static AppDelegate *AppDelegateKeeper;

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--self-test") == 0) { NSData *data=[@"{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}" dataUsingEncoding:NSUTF8StringEncoding]; NSCAssert([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]!=nil,@"JSON parser failed"); puts("CodexPet self-test passed"); return 0; }
        if (argc > 1 && strcmp(argv[1], "--dump") == 0) { for (TaskSnapshot *task in [CodexMonitor.new scan]) printf("%s\t%s\t%s\n",task.running?"running":"completed",task.source.UTF8String,task.title.UTF8String); return 0; }
        for (NSRunningApplication *running in [NSRunningApplication runningApplicationsWithBundleIdentifier:AgentLabel]) if (running.processIdentifier != getpid()) return 0;
        NSApplication *app=NSApplication.sharedApplication; AppDelegateKeeper=AppDelegate.new; app.delegate=AppDelegateKeeper; [app run];
    }
    return 0;
}

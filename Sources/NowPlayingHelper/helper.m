// Since macOS 15.4, MediaRemote only answers processes signed by Apple, so this
// library runs inside /usr/bin/perl. It writes one JSON object per line to stdout
// whenever the now-playing state changes and reads commands, one per line, from stdin.
#import <AppKit/AppKit.h>
#include <dlfcn.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetPIDFn)(dispatch_queue_t, void (^)(int));
typedef Boolean (*SendFn)(int, NSDictionary *);
typedef void (*SetElapsedFn)(double);
typedef void (*GetClientFn)(dispatch_queue_t, void (^)(id));
typedef NSString *(*ClientStringFn)(id);
typedef void *(*GetOriginFn)(void);
typedef void (*GetCommandsFn)(void *, dispatch_queue_t, void (^)(CFArrayRef));
typedef uint32_t (*CommandInfoCommandFn)(void *);
typedef Boolean (*CommandInfoEnabledFn)(void *);

// MRMediaRemoteCommand values beyond the transport ones in commandCode().
enum { kChangePlaybackRate = 19 };

static void emit(NSDictionary *obj) {
    if (![NSJSONSerialization isValidJSONObject:obj]) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static int commandCode(const char *line) {
    if (strncmp(line, "play", 4) == 0) return 0;
    if (strncmp(line, "pause", 5) == 0) return 1;
    if (strncmp(line, "toggle", 6) == 0) return 2;
    if (strncmp(line, "next", 4) == 0) return 4;
    if (strncmp(line, "previous", 8) == 0) return 5;
    return -1;
}

void nunsseop_nowplaying_run(void *perl, void *cv) {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mr) { emit(@{@"error": @"MediaRemote not found"}); return; }
    GetInfoFn getInfo = (GetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    GetPIDFn getPID = (GetPIDFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationPID");
    SendFn send = (SendFn)dlsym(mr, "MRMediaRemoteSendCommand");
    SetElapsedFn setElapsed = (SetElapsedFn)dlsym(mr, "MRMediaRemoteSetElapsedTime");
    GetClientFn getClient = (GetClientFn)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
    ClientStringFn clientBundle = (ClientStringFn)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
    ClientStringFn clientParentBundle = (ClientStringFn)dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
    GetOriginFn localOrigin = (GetOriginFn)dlsym(mr, "MRMediaRemoteGetLocalOrigin");
    GetCommandsFn getCommands = (GetCommandsFn)dlsym(mr, "MRMediaRemoteGetSupportedCommandsForOrigin");
    CommandInfoCommandFn infoCommand = (CommandInfoCommandFn)dlsym(mr, "MRMediaRemoteCommandInfoGetCommand");
    CommandInfoEnabledFn infoEnabled = (CommandInfoEnabledFn)dlsym(mr, "MRMediaRemoteCommandInfoGetEnabled");
    CFStringRef *rateOption = (CFStringRef *)dlsym(mr, "kMRMediaRemoteOptionPlaybackRate");
    if (!getInfo || !getPID || !send) { emit(@{@"error": @"MediaRemote symbols missing"}); return; }

    // Set after a rate change so the next poll reports the real rate even if the app ignored it.
    static volatile BOOL forceEmit = NO;
    // Set when the app has lost the artwork it was told to keep, so the next emit carries it again.
    static volatile BOOL resendArtwork = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        char line[64];
        while (fgets(line, sizeof line, stdin)) {
            if (strncmp(line, "seek ", 5) == 0) {
                double seconds = atof(line + 5);
                if (setElapsed && isfinite(seconds) && seconds >= 0) setElapsed(seconds);
                continue;
            }
            if (strncmp(line, "rate ", 5) == 0) {
                double rate = atof(line + 5);
                if (rateOption && isfinite(rate) && rate > 0 && rate <= 4)
                    send(kChangePlaybackRate, @{(__bridge NSString *)*rateOption: @(rate)});
                forceEmit = YES;
                continue;
            }
            if (strncmp(line, "resend", 6) == 0) {
                resendArtwork = YES;
                forceEmit = YES;
                continue;
            }
            int code = commandCode(line);
            if (code >= 0) send(code, nil);
        }
        exit(0);
    });

    dispatch_queue_t queue = dispatch_queue_create("nunsseop.nowplaying", DISPATCH_QUEUE_SERIAL);
    __block NSString *lastSignature = nil;
    __block NSData *lastArtwork = nil;

    void (^poll)(void) = ^{
        getInfo(queue, ^(NSDictionary *info) {
          void (^withClient)(id) = ^(id client) {
            NSString *clientID = nil;
            if (client && clientParentBundle) clientID = clientParentBundle(client);
            if (!clientID && client && clientBundle) clientID = clientBundle(client);
            void (^withCommands)(NSArray *) = ^(NSArray *commands) {
            getPID(queue, ^(int pid) {
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
                NSString *artist = info[@"kMRMediaRemoteNowPlayingInfoArtist"];
                NSString *album = info[@"kMRMediaRemoteNowPlayingInfoAlbum"];
                NSNumber *duration = info[@"kMRMediaRemoteNowPlayingInfoDuration"];
                NSNumber *elapsed = info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"];
                NSNumber *rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
                NSDate *timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                NSString *bundleID = clientID;
                if (!bundleID && pid > 0)
                    bundleID = [NSRunningApplication runningApplicationWithProcessIdentifier:pid].bundleIdentifier;

                if (title) out[@"title"] = title;
                if (artist) out[@"artist"] = artist;
                if (album) out[@"album"] = album;
                if (duration && isfinite(duration.doubleValue)) out[@"duration"] = duration;
                if (elapsed && isfinite(elapsed.doubleValue)) out[@"elapsed"] = elapsed;
                if (rate && isfinite(rate.doubleValue)) out[@"rate"] = rate;
                if (timestamp) out[@"timestamp"] = @(timestamp.timeIntervalSince1970);
                if (bundleID) out[@"bundleID"] = bundleID;
                if (info) out[@"active"] = @YES;
                if (commands) out[@"commands"] = commands;

                NSString *signature = [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@|%@|%lu|%d|%@",
                                       title, artist, album, duration, rate, elapsed, timestamp,
                                       (unsigned long)artwork.length, pid, [commands componentsJoinedByString:@","]];
                if (!forceEmit && [signature isEqualToString:lastSignature]) return;
                forceEmit = NO;
                lastSignature = signature;
                if (resendArtwork) {
                    resendArtwork = NO;
                    lastArtwork = nil;
                }
                // Artwork goes out only when it changes; "artworkUnchanged" tells the app to keep what it has.
                // Without a title the app drops the update, so the next one with a title sends the artwork again.
                if (!artwork || title.length == 0) {
                    lastArtwork = nil;
                } else if ([artwork isEqualToData:lastArtwork]) {
                    out[@"artworkUnchanged"] = @YES;
                } else {
                    lastArtwork = artwork;
                    out[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
                }
                emit(out);
            });
            };
            // Enabled command codes of the now-playing app, so the notch only offers what it accepts.
            if (!localOrigin || !getCommands || !infoCommand || !infoEnabled) { withCommands(nil); return; }
            getCommands(localOrigin(), queue, ^(CFArrayRef list) {
                NSMutableArray *codes = [NSMutableArray array];
                for (CFIndex i = 0; list && i < CFArrayGetCount(list); i++) {
                    void *item = (void *)CFArrayGetValueAtIndex(list, i);
                    if (infoEnabled(item)) [codes addObject:@(infoCommand(item))];
                }
                withCommands(codes);
            });
          };
          if (getClient) getClient(queue, withClient); else withClient(nil);
        });
    };

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, NSEC_PER_SEC, NSEC_PER_SEC / 10);
    dispatch_source_set_event_handler(timer, poll);
    dispatch_resume(timer);

    dispatch_main();
}

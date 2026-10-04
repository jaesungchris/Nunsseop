// Since macOS 15.4, MediaRemote only answers processes signed by Apple, so this
// library runs inside /usr/bin/perl. It writes one JSON object per line to stdout
// whenever the now-playing state changes and reads commands, one per line, from stdin.
#import <AppKit/AppKit.h>
#include <dlfcn.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetPIDFn)(dispatch_queue_t, void (^)(int));
typedef Boolean (*SendFn)(int, NSDictionary *);
typedef void (*GetClientFn)(dispatch_queue_t, void (^)(id));
typedef NSString *(*ClientStringFn)(id);

static void emit(NSDictionary *obj) {
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

void notchapp_nowplaying_run(void *perl, void *cv) {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mr) { emit(@{@"error": @"MediaRemote not found"}); return; }
    GetInfoFn getInfo = (GetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    GetPIDFn getPID = (GetPIDFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationPID");
    SendFn send = (SendFn)dlsym(mr, "MRMediaRemoteSendCommand");
    GetClientFn getClient = (GetClientFn)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
    ClientStringFn clientBundle = (ClientStringFn)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
    ClientStringFn clientParentBundle = (ClientStringFn)dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
    if (!getInfo || !getPID || !send) { emit(@{@"error": @"MediaRemote symbols missing"}); return; }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        char line[64];
        while (fgets(line, sizeof line, stdin)) {
            int code = commandCode(line);
            if (code >= 0) send(code, nil);
        }
        exit(0);
    });

    dispatch_queue_t queue = dispatch_queue_create("notchapp.nowplaying", DISPATCH_QUEUE_SERIAL);
    __block NSString *lastSignature = nil;

    void (^poll)(void) = ^{
        getInfo(queue, ^(NSDictionary *info) {
          void (^withClient)(id) = ^(id client) {
            NSString *clientID = nil;
            if (client && clientParentBundle) clientID = clientParentBundle(client);
            if (!clientID && client && clientBundle) clientID = clientBundle(client);
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
                if (duration) out[@"duration"] = duration;
                if (elapsed) out[@"elapsed"] = elapsed;
                if (rate) out[@"rate"] = rate;
                if (timestamp) out[@"timestamp"] = @(timestamp.timeIntervalSince1970);
                if (bundleID) out[@"bundleID"] = bundleID;
                if (info) out[@"active"] = @YES;

                NSString *signature = [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@|%@|%lu|%d",
                                       title, artist, album, duration, rate, elapsed, timestamp,
                                       (unsigned long)artwork.length, pid];
                if ([signature isEqualToString:lastSignature]) return;
                lastSignature = signature;
                if (artwork) out[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
                emit(out);
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

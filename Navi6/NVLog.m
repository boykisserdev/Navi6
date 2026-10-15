#import "NVLog.h"
#include <execinfo.h>
#include <signal.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#import <objc/runtime.h>
#include <mach-o/dyld.h>

static int sFD = -1;
static NSString *sPrevious;
static CFAbsoluteTime sStart;

static NSString *NVTrailPath(void) {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0] stringByAppendingPathComponent:@"trail.log"];
}

void NVLogStart(void) {
    sStart = CFAbsoluteTimeGetCurrent();
    sPrevious = [NSString stringWithContentsOfFile:NVTrailPath() encoding:NSUTF8StringEncoding error:nil];
    sFD = open([NVTrailPath() fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0644);
}

void NVLog(NSString *format, ...) {
    if (sFD < 0) return;
    va_list args; va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"%7.2f %@\n", CFAbsoluteTimeGetCurrent() - sStart, msg];
    const char *c = [line UTF8String];
    if (c) write(sFD, c, strlen(c));
}

static void NVSignalHandler(int sig) {
    if (sFD >= 0) {
        char buf[64];
        int n = snprintf(buf, sizeof(buf), "\n[SIGNAL %d]\n", sig);
        write(sFD, buf, n);
        void *frames[48];
        int cnt = backtrace(frames, 48);
        backtrace_symbols_fd(frames, cnt, sFD);
        write(sFD, "\n[crashed]\n", 11);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

void NVLogInstallCrashHandlers(void) {
    int sigs[] = { SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGFPE, SIGTRAP };
    for (unsigned i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) signal(sigs[i], NVSignalHandler);
}

static NSString *NVSymbolicate(uintptr_t offset) {
    const struct mach_header *hdr = _dyld_get_image_header(0);
    const char *mainImage = _dyld_get_image_name(0);
    uintptr_t target = ((uintptr_t)hdr + offset) & ~(uintptr_t)1;
    uintptr_t best = 0;
    NSString *bestName = nil;
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        const char *img = class_getImageName(classes[i]);
        if (!img || strcmp(img, mainImage) != 0) continue;
        for (int meta = 0; meta < 2; meta++) {
            Class c = meta ? object_getClass(classes[i]) : classes[i];
            unsigned int mc = 0;
            Method *ms = class_copyMethodList(c, &mc);
            for (unsigned int j = 0; j < mc; j++) {
                uintptr_t imp = (uintptr_t)method_getImplementation(ms[j]) & ~(uintptr_t)1;
                if (imp <= target && imp > best) {
                    best = imp;
                    bestName = [NSString stringWithFormat:@"%c[%s %s]", meta ? '+' : '-', class_getName(classes[i]), sel_getName(method_getName(ms[j]))];
                }
            }
            free(ms);
        }
    }
    free(classes);
    if (!bestName || target - best > 12000) return nil;
    return [NSString stringWithFormat:@"%@ +%lu", bestName, (unsigned long)(target - best)];
}

NSString *NVLogPreviousCrash(void) {
    if (!sPrevious.length) return nil;
    NSMutableArray *lines = [[sPrevious componentsSeparatedByString:@"\n"] mutableCopy];
    while (lines.count && ![[lines lastObject] length]) [lines removeLastObject];
    if (!lines.count) return nil;
    NSString *last = [lines lastObject];
    if ([last rangeOfString:@"[clean]"].location != NSNotFound || [last rangeOfString:@"[background]"].location != NSNotFound) return nil;

    NSMutableArray *keep = [NSMutableArray array];
    for (NSString *line in lines) {
        NSRange navi = [line rangeOfString:@"Navi6 + "];
        if (navi.location != NSNotFound) {
            NSScanner *sc = [NSScanner scannerWithString:[line substringFromIndex:navi.location + navi.length]];
            long long off = 0;
            if ([sc scanLongLong:&off]) {
                NSString *sym = NVSymbolicate((uintptr_t)off);
                NSString *frameNo = [[line componentsSeparatedByString:@" "] objectAtIndex:0];
                [keep addObject:[NSString stringWithFormat:@"#%@ %@", frameNo, sym ?: [NSString stringWithFormat:@"Navi6+%lld", off]]];
                continue;
            }
        }
        if ([line rangeOfString:@"EXCEPTION"].location != NSNotFound || [line rangeOfString:@"[SIGNAL"].location != NSNotFound
            || [line rangeOfString:@"[crashed]"].location != NSNotFound) { [keep addObject:line]; continue; }
        NSScanner *t = [NSScanner scannerWithString:line];
        double d;
        if ([t scanDouble:&d] && [line rangeOfString:@"0x"].location == NSNotFound) [keep addObject:line];
    }
    NSUInteger from = keep.count > 30 ? keep.count - 30 : 0;
    return [[keep subarrayWithRange:NSMakeRange(from, keep.count - from)] componentsJoinedByString:@"\n"];
}

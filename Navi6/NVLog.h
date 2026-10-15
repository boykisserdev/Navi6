#import <Foundation/Foundation.h>

void NVLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
void NVLogStart(void);
void NVLogInstallCrashHandlers(void);
NSString *NVLogPreviousCrash(void);

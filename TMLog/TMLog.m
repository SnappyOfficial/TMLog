#import "TMLog.h"
#import <UIKit/UIKit.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <arpa/inet.h>

@interface TMLog () {
    
    CFSocketRef socket;
    NSData *addrData;
}

@end

@implementation TMLog

+ (id)startWithHost:(NSString *)host port:(int)port {
    static TMLog *shared = nil;
    
    @synchronized(self) {
        if (shared == nil)
            shared = [[self alloc] initWithHost:host port:port];
    }
    return shared;
}

- (id) initWithHost:(NSString *)host port:(int)port {
    if (self = [super init]) {
        if ([self canSendLogs]) {
            self.host = host;
            self.port = port;
            
            pipe = [NSPipe pipe];
            stderrWriteFileHandle = [pipe fileHandleForWriting];
            stderrReadFileHandle = [pipe fileHandleForReading];
            
            dup2([stderrWriteFileHandle fileDescriptor], STDOUT_FILENO);
            dup2([stderrWriteFileHandle fileDescriptor], STDERR_FILENO);
            
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationReceived:) name:NSFileHandleReadCompletionNotification object:stderrReadFileHandle];
            [stderrReadFileHandle readInBackgroundAndNotify];
            
            socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_DGRAM, IPPROTO_UDP, 0, NULL, NULL);
            
            struct hostent *hostname_to_ip = gethostbyname([self.host cStringUsingEncoding:NSUTF8StringEncoding]);
            
            struct sockaddr_in addr;
            memset(&addr, 0, sizeof(addr));
            addr.sin_len = sizeof(addr);
            addr.sin_family = AF_INET;
            addr.sin_port = htons(self.port);
            
            inet_aton(inet_ntoa(* (struct in_addr *)hostname_to_ip->h_addr_list[0]), &addr.sin_addr);
            
            //convert the struct to a NSData object
            addrData = [NSData dataWithBytes:&addr length:sizeof(addr)];
        }
    }
    
    return self;
}

- (void)notificationReceived:(NSNotification *)notification {
    [stderrReadFileHandle readInBackgroundAndNotify];
    [self sendLog:[self getLogMessage:notification]];
}

- (BOOL) canSendLogs {
#if !(TARGET_IPHONE_SIMULATOR || DEBUG)
    return true;
#else 
    return false;
#endif
}

- (NSString *) getLogMessage:(NSNotification *)notification {
    NSData *dataReceived = [[notification userInfo] objectForKey: NSFileHandleNotificationDataItem];
    
    if (dataReceived != nil) {
        return [[NSString alloc] initWithData: dataReceived  encoding: NSUTF8StringEncoding];
    }
    
    return @"";
}

- (void) sendLog:(NSString *)logMessage {
    if (logMessage == nil)
        return;

    CFSocketSendData(socket, (CFDataRef)addrData, (CFDataRef)[logMessage dataUsingEncoding:NSUTF8StringEncoding], 0);
}

@end

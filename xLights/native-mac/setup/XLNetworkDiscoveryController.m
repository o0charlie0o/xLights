/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLNetworkDiscoveryController.h"
#import "XLMacVendorLookup.h"
#import "../XLEngineBridge.h"
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>

/// Internal storage for discovered controllers.
/// Uses C array to avoid heap corruption from ObjC/C++ mixing.
static XLDiscoveredController _discoveredControllers[XL_MAX_DISCOVERED_CONTROLLERS];
static size_t _discoveredCount = 0;
static pthread_mutex_t _discoveryMutex = PTHREAD_MUTEX_INITIALIZER;

@interface XLNetworkDiscoveryController ()

@property (nonatomic, assign, readwrite) XLDiscoveryState state;
@property (nonatomic, strong) dispatch_source_t pingTimer;
@property (nonatomic, strong) dispatch_queue_t discoveryQueue;
@property (nonatomic, assign) BOOL cancelRequested;

@end

@implementation XLNetworkDiscoveryController

- (instancetype)init {
    self = [super init];
    if (self) {
        _state = XLDiscoveryStateIdle;
        _discoveryTimeout = 5.0;
        _pingInterval = 30.0;
        _cancelRequested = NO;
        _discoveryQueue = dispatch_queue_create("org.xlights.discovery", DISPATCH_QUEUE_SERIAL);

        // Preload MAC vendor database
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            [[XLMacVendorLookup sharedInstance] loadDatabase];
        });
    }
    return self;
}

- (void)dealloc {
    [self stopBackgroundPing];
    [self cancelDiscovery];
}

- (NSUInteger)discoveredCount {
    pthread_mutex_lock(&_discoveryMutex);
    NSUInteger count = _discoveredCount;
    pthread_mutex_unlock(&_discoveryMutex);
    return count;
}

#pragma mark - Discovery Operations

- (void)startDiscovery {
    if (_state == XLDiscoveryStateScanning) {
        return;
    }

    _cancelRequested = NO;
    self.state = XLDiscoveryStateScanning;

    // Notify delegate of state change
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(discoveryController:didChangeState:)]) {
            [self.delegate discoveryController:self didChangeState:self.state];
        }
    });

    // Run discovery on background queue
    dispatch_async(_discoveryQueue, ^{
        [self performDiscovery];
    });
}

- (void)cancelDiscovery {
    if (_state != XLDiscoveryStateScanning) {
        return;
    }

    _cancelRequested = YES;
}

- (void)performDiscovery {
    pthread_mutex_lock(&_discoveryMutex);
    _discoveredCount = 0;
    memset(_discoveredControllers, 0, sizeof(_discoveredControllers));
    pthread_mutex_unlock(&_discoveryMutex);

    // Get local network interfaces for subnet scanning
    NSArray<NSString *> *localIPs = [self getLocalIPAddresses];
    NSArray<NSString *> *existingControllerNames = [_engineBridge getControllerNames];
    NSMutableSet<NSString *> *existingIPs = [NSMutableSet set];

    for (NSString *name in existingControllerNames) {
        NSDictionary *info = [_engineBridge getControllerInfo:name];
        NSString *ip = info[@"ip"];
        if (ip) {
            [existingIPs addObject:ip];
        }
    }

    // Perform multicast/broadcast discovery
    [self discoverViaBroadcast:localIPs existingIPs:existingIPs existingNames:existingControllerNames];

    // Check if cancelled
    if (_cancelRequested) {
        self.state = XLDiscoveryStateIdle;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(discoveryController:didChangeState:)]) {
                [self.delegate discoveryController:self didChangeState:self.state];
            }
        });
        return;
    }

    // Complete discovery
    self.state = XLDiscoveryStateComplete;

    pthread_mutex_lock(&_discoveryMutex);
    NSUInteger count = _discoveredCount;
    pthread_mutex_unlock(&_discoveryMutex);

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(discoveryController:didChangeState:)]) {
            [self.delegate discoveryController:self didChangeState:self.state];
        }

        if ([self.delegate respondsToSelector:@selector(discoveryController:didDiscoverControllers:count:)]) {
            pthread_mutex_lock(&_discoveryMutex);
            [self.delegate discoveryController:self
                       didDiscoverControllers:_discoveredControllers
                                        count:count];
            pthread_mutex_unlock(&_discoveryMutex);
        }
    });
}

- (void)discoverViaBroadcast:(NSArray<NSString *> *)localIPs
                 existingIPs:(NSSet<NSString *> *)existingIPs
               existingNames:(NSArray<NSString *> *)existingNames {
    // Ports commonly used by xLights-compatible controllers
    // E1.31: 5568, ArtNet: 6454, FPP: 32320, 32322
    int discoveryPorts[] = { 32320, 32322, 6454, 5568 };
    int portCount = sizeof(discoveryPorts) / sizeof(discoveryPorts[0]);

    for (NSString *localIP in localIPs) {
        if (_cancelRequested) return;

        // Calculate broadcast address from local IP (assuming /24 subnet)
        NSString *broadcastIP = [self broadcastAddressForIP:localIP];
        if (!broadcastIP) continue;

        for (int p = 0; p < portCount; p++) {
            if (_cancelRequested) return;

            int port = discoveryPorts[p];
            [self sendDiscoveryProbe:broadcastIP port:port];
        }
    }

    // Wait for responses
    [self waitForDiscoveryResponses];

    // Look up MAC vendors for discovered controllers
    [self enrichWithMacVendorInfo];

    // Mark already-configured controllers
    pthread_mutex_lock(&_discoveryMutex);
    for (size_t i = 0; i < _discoveredCount; i++) {
        NSString *ip = [NSString stringWithUTF8String:_discoveredControllers[i].ip];
        if ([existingIPs containsObject:ip]) {
            _discoveredControllers[i].alreadyConfigured = 1;
            // Find the existing name
            for (NSString *name in existingNames) {
                NSDictionary *info = [_engineBridge getControllerInfo:name];
                if ([info[@"ip"] isEqualToString:ip]) {
                    xl_safe_strcpy(_discoveredControllers[i].existingName,
                                   sizeof(_discoveredControllers[i].existingName),
                                   [name UTF8String]);
                    break;
                }
            }
        }
    }
    pthread_mutex_unlock(&_discoveryMutex);
}

- (void)sendDiscoveryProbe:(NSString *)broadcastIP port:(int)port {
    int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sock < 0) return;

    int broadcast = 1;
    setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcast, sizeof(broadcast));

    struct timeval tv;
    tv.tv_sec = 1;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    inet_pton(AF_INET, [broadcastIP UTF8String], &addr.sin_addr);

    // Send FPP-style discovery packet
    const char *probe = "xLights Discovery";
    sendto(sock, probe, strlen(probe), 0, (struct sockaddr *)&addr, sizeof(addr));

    // Send ArtNet poll packet
    if (port == 6454) {
        uint8_t artnetPoll[14] = {
            'A', 'r', 't', '-', 'N', 'e', 't', 0x00,  // ID
            0x00, 0x20,                               // OpCode: ArtPoll (little endian)
            0x00, 0x0E,                               // Protocol version
            0x00, 0x00                                // Flags
        };
        sendto(sock, artnetPoll, sizeof(artnetPoll), 0, (struct sockaddr *)&addr, sizeof(addr));
    }

    close(sock);
}

- (void)waitForDiscoveryResponses {
    // Create a receiving socket
    int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sock < 0) return;

    int reuse = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &reuse, sizeof(reuse));

    struct timeval tv;
    tv.tv_sec = (long)_discoveryTimeout;
    tv.tv_usec = ((_discoveryTimeout - tv.tv_sec) * 1000000);
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    struct sockaddr_in bindAddr;
    memset(&bindAddr, 0, sizeof(bindAddr));
    bindAddr.sin_family = AF_INET;
    bindAddr.sin_port = htons(32321); // FPP response port
    bindAddr.sin_addr.s_addr = INADDR_ANY;

    if (bind(sock, (struct sockaddr *)&bindAddr, sizeof(bindAddr)) < 0) {
        close(sock);
        return;
    }

    // Listen for responses
    uint8_t buffer[2048];
    struct sockaddr_in fromAddr;
    socklen_t fromLen = sizeof(fromAddr);

    NSDate *endTime = [NSDate dateWithTimeIntervalSinceNow:_discoveryTimeout];
    while ([[NSDate date] compare:endTime] == NSOrderedAscending && !_cancelRequested) {
        ssize_t len = recvfrom(sock, buffer, sizeof(buffer) - 1, 0,
                                (struct sockaddr *)&fromAddr, &fromLen);
        if (len > 0) {
            buffer[len] = 0;
            char ipStr[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &fromAddr.sin_addr, ipStr, sizeof(ipStr));
            [self processDiscoveryResponse:buffer length:len fromIP:ipStr];
        }
    }

    close(sock);
}

- (void)processDiscoveryResponse:(uint8_t *)buffer length:(ssize_t)length fromIP:(const char *)ip {
    pthread_mutex_lock(&_discoveryMutex);

    // Check if we already have this IP
    for (size_t i = 0; i < _discoveredCount; i++) {
        if (strcmp(_discoveredControllers[i].ip, ip) == 0) {
            pthread_mutex_unlock(&_discoveryMutex);
            return;
        }
    }

    if (_discoveredCount >= XL_MAX_DISCOVERED_CONTROLLERS) {
        pthread_mutex_unlock(&_discoveryMutex);
        return;
    }

    XLDiscoveredController *dc = &_discoveredControllers[_discoveredCount];
    xl_init_discovered_controller(dc);
    xl_safe_strcpy(dc->ip, sizeof(dc->ip), ip);

    // Try to parse the response as JSON (FPP/Falcon style)
    NSData *data = [NSData dataWithBytes:buffer length:length];
    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    if (json && !error) {
        if (json[@"HostName"]) {
            xl_safe_strcpy(dc->hostname, sizeof(dc->hostname), [json[@"HostName"] UTF8String]);
        }
        if (json[@"fppMode"]) {
            xl_safe_strcpy(dc->mode, sizeof(dc->mode), [json[@"fppMode"] UTF8String]);
        }
        if (json[@"Version"]) {
            xl_safe_strcpy(dc->version, sizeof(dc->version), [json[@"Version"] UTF8String]);
        }
        if (json[@"Platform"]) {
            xl_safe_strcpy(dc->platform, sizeof(dc->platform), [json[@"Platform"] UTF8String]);
        }
        if (json[@"model"]) {
            xl_safe_strcpy(dc->platformModel, sizeof(dc->platformModel), [json[@"model"] UTF8String]);
        }
        if (json[@"channelRanges"]) {
            xl_safe_strcpy(dc->description, sizeof(dc->description), [json[@"channelRanges"] UTF8String]);
        }

        // Try to identify vendor from platform
        NSString *platform = json[@"Platform"];
        if ([platform containsString:@"Falcon"]) {
            xl_safe_strcpy(dc->vendor, sizeof(dc->vendor), "Falcon");
        } else if ([platform containsString:@"FPP"] || [platform containsString:@"Raspberry"]) {
            xl_safe_strcpy(dc->vendor, sizeof(dc->vendor), "FPP");
        } else if ([platform containsString:@"ESP"]) {
            xl_safe_strcpy(dc->vendor, sizeof(dc->vendor), "ESPixelStick");
        }
    } else {
        // Check for ArtNet reply
        if (length >= 8 && memcmp(buffer, "Art-Net", 7) == 0) {
            xl_safe_strcpy(dc->vendor, sizeof(dc->vendor), "ArtNet Device");
            xl_safe_strcpy(dc->mode, sizeof(dc->mode), "ArtNet");
        }
    }

    // Set default hostname if not provided
    if (dc->hostname[0] == '\0') {
        xl_safe_strcpy(dc->hostname, sizeof(dc->hostname), ip);
    }

    _discoveredCount++;
    pthread_mutex_unlock(&_discoveryMutex);
}

- (void)enrichWithMacVendorInfo {
    // MAC vendor lookup would require ARP table access or additional
    // network probing. For now, we rely on the controller's self-reported
    // vendor information from the discovery response.
    //
    // Future enhancement: Use getifaddrs + ARP to get MAC addresses,
    // then look up vendors using XLMacVendorLookup.
}

- (NSArray<NSString *> *)getLocalIPAddresses {
    NSMutableArray<NSString *> *addresses = [NSMutableArray array];
    struct ifaddrs *interfaces = NULL;

    if (getifaddrs(&interfaces) == 0) {
        struct ifaddrs *temp = interfaces;
        while (temp != NULL) {
            if (temp->ifa_addr && temp->ifa_addr->sa_family == AF_INET) {
                // Check if interface is up and not loopback
                if ((temp->ifa_flags & IFF_UP) && !(temp->ifa_flags & IFF_LOOPBACK)) {
                    char addr[INET_ADDRSTRLEN];
                    inet_ntop(AF_INET, &((struct sockaddr_in *)temp->ifa_addr)->sin_addr,
                              addr, sizeof(addr));
                    [addresses addObject:[NSString stringWithUTF8String:addr]];
                }
            }
            temp = temp->ifa_next;
        }
        freeifaddrs(interfaces);
    }

    return addresses;
}

- (NSString *)broadcastAddressForIP:(NSString *)ip {
    // Simple /24 subnet assumption
    NSArray<NSString *> *octets = [ip componentsSeparatedByString:@"."];
    if (octets.count != 4) return nil;
    return [NSString stringWithFormat:@"%@.%@.%@.255", octets[0], octets[1], octets[2]];
}

#pragma mark - Accessor Methods

- (BOOL)getDiscoveredController:(XLDiscoveredController *)outController atIndex:(NSUInteger)index {
    if (!outController) return NO;

    pthread_mutex_lock(&_discoveryMutex);
    BOOL success = NO;
    if (index < _discoveredCount) {
        memcpy(outController, &_discoveredControllers[index], sizeof(XLDiscoveredController));
        success = YES;
    }
    pthread_mutex_unlock(&_discoveryMutex);

    return success;
}

- (NSArray<NSDictionary *> *)discoveredControllersAsDictionaries {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];

    pthread_mutex_lock(&_discoveryMutex);
    for (size_t i = 0; i < _discoveredCount; i++) {
        XLDiscoveredController *dc = &_discoveredControllers[i];
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];

        dict[@"ip"] = [NSString stringWithUTF8String:dc->ip];
        dict[@"hostname"] = [NSString stringWithUTF8String:dc->hostname];
        dict[@"vendor"] = [NSString stringWithUTF8String:dc->vendor];
        dict[@"model"] = [NSString stringWithUTF8String:dc->model];
        dict[@"mode"] = [NSString stringWithUTF8String:dc->mode];
        dict[@"version"] = [NSString stringWithUTF8String:dc->version];
        dict[@"platform"] = [NSString stringWithUTF8String:dc->platform];
        dict[@"description"] = [NSString stringWithUTF8String:dc->description];
        dict[@"alreadyConfigured"] = @(dc->alreadyConfigured);
        dict[@"existingName"] = [NSString stringWithUTF8String:dc->existingName];

        [result addObject:dict];
    }
    pthread_mutex_unlock(&_discoveryMutex);

    return result;
}

#pragma mark - Configuration Operations

- (BOOL)addDiscoveredControllerAtIndex:(NSUInteger)index {
    XLDiscoveredController dc;
    if (![self getDiscoveredController:&dc atIndex:index]) {
        return NO;
    }

    NSString *name = [NSString stringWithUTF8String:dc.hostname];
    if (name.length == 0) {
        name = [NSString stringWithUTF8String:dc.ip];
    }

    return [self addDiscoveredControllerAtIndex:index withName:name];
}

- (BOOL)addDiscoveredControllerAtIndex:(NSUInteger)index withName:(NSString *)name {
    XLDiscoveredController dc;
    if (![self getDiscoveredController:&dc atIndex:index]) {
        return NO;
    }

    // TODO: Once engine bridge supports addController, use it directly
    // For now, log the action
    NSLog(@"[XLNetworkDiscoveryController] Would add controller: %@ at IP %s", name, dc.ip);

    return YES;
}

#pragma mark - Ping Operations

- (BOOL)isBackgroundPingActive {
    return _pingTimer != nil;
}

- (void)startBackgroundPing {
    if (_pingTimer || _pingInterval <= 0) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    _pingTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                          dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));

    dispatch_source_set_timer(_pingTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_pingInterval * NSEC_PER_SEC)),
                              (uint64_t)(_pingInterval * NSEC_PER_SEC),
                              (uint64_t)(1.0 * NSEC_PER_SEC));

    dispatch_source_set_event_handler(_pingTimer, ^{
        [weakSelf pingAllControllersNow];
    });

    dispatch_resume(_pingTimer);
}

- (void)stopBackgroundPing {
    if (_pingTimer) {
        dispatch_source_cancel(_pingTimer);
        _pingTimer = nil;
    }
}

- (void)pingAllControllersNow {
    NSArray<NSString *> *names = [_engineBridge getControllerNames];
    for (NSString *name in names) {
        [self pingControllerNamed:name];
    }
}

- (void)pingControllerNamed:(NSString *)name {
    if (!name) return;

    NSDictionary *info = [_engineBridge getControllerInfo:name];
    NSString *ip = info[@"ip"];
    if (!ip) return;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        XLPingState pingState = [weakSelf performPingForIP:ip];

        dispatch_async(dispatch_get_main_queue(), ^{
            if ([weakSelf.delegate respondsToSelector:@selector(discoveryController:didUpdatePingStatus:forControllerName:)]) {
                [weakSelf.delegate discoveryController:weakSelf
                                    didUpdatePingStatus:pingState
                                      forControllerName:name];
            }
        });
    });
}

- (XLPingState)performPingForIP:(NSString *)ip {
    // Simple TCP connect test to common ports
    int ports[] = { 80, 443, 32320, 4048 };
    int portCount = sizeof(ports) / sizeof(ports[0]);

    for (int i = 0; i < portCount; i++) {
        int sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock < 0) continue;

        struct timeval tv;
        tv.tv_sec = 2;
        tv.tv_usec = 0;
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons(ports[i]);
        inet_pton(AF_INET, [ip UTF8String], &addr.sin_addr);

        int result = connect(sock, (struct sockaddr *)&addr, sizeof(addr));
        close(sock);

        if (result == 0) {
            if (ports[i] == 80 || ports[i] == 443) {
                return XLPingStateWebOK;
            }
            return XLPingStateOK;
        }
    }

    return XLPingStateAllFailed;
}

@end

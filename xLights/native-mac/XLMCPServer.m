/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLMCPServer.h"
#import "XLEngineBridge.h"
#import "XLEffectPresetsWindowController.h"
#import <Network/Network.h>

static const uint16_t kDefaultPort = 1225;

#pragma mark - Client Connection

/// Represents a single connected MCP client.
@interface XLMCPClientConnection : NSObject
@property (nonatomic, strong) nw_connection_t connection;
@property (nonatomic, strong) NSMutableData *receiveBuffer;
@property (nonatomic, assign) BOOL initialized;
@end

@implementation XLMCPClientConnection
- (instancetype)initWithConnection:(nw_connection_t)connection {
    self = [super init];
    if (self) {
        _connection = connection;
        _receiveBuffer = [NSMutableData data];
        _initialized = NO;
    }
    return self;
}
@end

#pragma mark - XLMCPServer

@interface XLMCPServer ()
@property (nonatomic, strong) nw_listener_t listener;
@property (nonatomic, strong) NSMutableArray<XLMCPClientConnection *> *clients;
@property (nonatomic, strong) dispatch_queue_t serverQueue;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) uint16_t activePort;
@end

@implementation XLMCPServer

- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge {
    self = [super init];
    if (self) {
        _engineBridge = engineBridge;
        _clients = [NSMutableArray array];
        _serverQueue = dispatch_queue_create("org.xlights.mcpserver", DISPATCH_QUEUE_SERIAL);
        _running = NO;
        _activePort = 0;
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

#pragma mark - Server Lifecycle

- (BOOL)start {
    return [self startOnPort:kDefaultPort];
}

- (BOOL)startOnPort:(uint16_t)port {
    if (_running) {
        NSLog(@"MCP Server: Already running on port %u", _activePort);
        return YES;
    }

    nw_parameters_t parameters = nw_parameters_create_secure_tcp(
        NW_PARAMETERS_DISABLE_PROTOCOL,  // No TLS
        NW_PARAMETERS_DEFAULT_CONFIGURATION  // Default TCP
    );

    // Bind to localhost only
    nw_endpoint_t endpoint = nw_endpoint_create_host("127.0.0.1", [[NSString stringWithFormat:@"%u", port] UTF8String]);
    nw_parameters_set_local_endpoint(parameters, endpoint);

    // Enable address reuse
    nw_parameters_set_reuse_local_address(parameters, true);

    _listener = nw_listener_create(parameters);
    if (!_listener) {
        NSLog(@"MCP Server: Failed to create listener");
        return NO;
    }

    nw_listener_set_queue(_listener, _serverQueue);

    __weak typeof(self) weakSelf = self;

    nw_listener_set_new_connection_handler(_listener, ^(nw_connection_t connection) {
        [weakSelf handleNewConnection:connection];
    });

    __block BOOL startSuccess = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    nw_listener_set_state_changed_handler(_listener, ^(nw_listener_state_t state, nw_error_t error) {
        switch (state) {
            case nw_listener_state_ready:
                NSLog(@"MCP Server: Listening on 127.0.0.1:%u", port);
                startSuccess = YES;
                dispatch_semaphore_signal(sem);
                break;
            case nw_listener_state_failed:
                NSLog(@"MCP Server: Failed to start on port %u: %@", port, error);
                startSuccess = NO;
                dispatch_semaphore_signal(sem);
                break;
            case nw_listener_state_cancelled:
                NSLog(@"MCP Server: Listener cancelled");
                break;
            default:
                break;
        }
    });

    nw_listener_start(_listener);

    // Wait up to 2 seconds for the listener to start
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));

    if (startSuccess) {
        _running = YES;
        _activePort = port;
    } else {
        nw_listener_cancel(_listener);
        _listener = nil;
    }

    return startSuccess;
}

- (void)stop {
    if (!_running) return;

    _running = NO;
    _activePort = 0;

    // Cancel all client connections
    for (XLMCPClientConnection *client in _clients) {
        nw_connection_cancel(client.connection);
    }
    [_clients removeAllObjects];

    // Cancel the listener
    if (_listener) {
        nw_listener_cancel(_listener);
        _listener = nil;
    }

    NSLog(@"MCP Server: Stopped");
}

- (BOOL)isRunning {
    return _running;
}

- (uint16_t)port {
    return _activePort;
}

- (NSUInteger)clientCount {
    return _clients.count;
}

#pragma mark - Connection Handling

- (void)handleNewConnection:(nw_connection_t)connection {
    NSLog(@"MCP Server: New client connection");

    XLMCPClientConnection *client = [[XLMCPClientConnection alloc] initWithConnection:connection];
    [_clients addObject:client];

    __weak typeof(self) weakSelf = self;
    __weak XLMCPClientConnection *weakClient = client;

    nw_connection_set_queue(connection, _serverQueue);

    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
        if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) {
            NSLog(@"MCP Server: Client disconnected");
            __strong typeof(weakSelf) strongSelf = weakSelf;
            __strong XLMCPClientConnection *strongClient = weakClient;
            if (strongSelf && strongClient) {
                [strongSelf->_clients removeObject:strongClient];
            }
        }
    });

    nw_connection_start(connection);
    [self receiveFromClient:client];
}

- (void)receiveFromClient:(XLMCPClientConnection *)client {
    __weak typeof(self) weakSelf = self;
    __weak XLMCPClientConnection *weakClient = client;

    nw_connection_receive(client.connection, 1, 65536, ^(dispatch_data_t content, nw_content_context_t context,
                                                          bool is_complete, nw_error_t error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong XLMCPClientConnection *strongClient = weakClient;
        if (!strongSelf || !strongClient) return;

        if (error) {
            NSLog(@"MCP Server: Receive error: %@", error);
            nw_connection_cancel(strongClient.connection);
            return;
        }

        if (content) {
            // Append received data to buffer
            dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
                [strongClient.receiveBuffer appendBytes:buffer length:size];
                return true;
            });

            // Process complete messages (newline-delimited)
            [strongSelf processBufferForClient:strongClient];
        }

        if (is_complete) {
            nw_connection_cancel(strongClient.connection);
            return;
        }

        // Continue receiving
        [strongSelf receiveFromClient:strongClient];
    });
}

- (void)processBufferForClient:(XLMCPClientConnection *)client {
    while (YES) {
        NSRange newlineRange = [client.receiveBuffer rangeOfData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]
                                                        options:0
                                                          range:NSMakeRange(0, client.receiveBuffer.length)];
        if (newlineRange.location == NSNotFound) break;

        NSData *messageData = [client.receiveBuffer subdataWithRange:NSMakeRange(0, newlineRange.location)];
        [client.receiveBuffer replaceBytesInRange:NSMakeRange(0, newlineRange.location + 1) withBytes:NULL length:0];

        if (messageData.length == 0) continue;

        NSString *messageStr = [[NSString alloc] initWithData:messageData encoding:NSUTF8StringEncoding];
        if (!messageStr) continue;

        NSString *response = [self processMessage:messageStr forClient:client];
        if (response && response.length > 0) {
            NSString *responseWithNewline = [response stringByAppendingString:@"\n"];
            NSData *responseData = [responseWithNewline dataUsingEncoding:NSUTF8StringEncoding];

            nw_connection_send(client.connection,
                             dispatch_data_create(responseData.bytes, responseData.length,
                                                  _serverQueue, DISPATCH_DATA_DESTRUCTOR_DEFAULT),
                             NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true,
                             ^(nw_error_t sendError) {
                if (sendError) {
                    NSLog(@"MCP Server: Send error: %@", sendError);
                }
            });
        }
    }
}

#pragma mark - JSON-RPC Message Processing

- (NSString *)processMessage:(NSString *)message forClient:(XLMCPClientConnection *)client {
    NSError *jsonError = nil;
    NSData *msgData = [message dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *request = [NSJSONSerialization JSONObjectWithData:msgData options:0 error:&jsonError];

    if (jsonError || ![request isKindOfClass:[NSDictionary class]]) {
        return [self makeErrorWithId:@"null" code:-32700 message:@"Parse error"];
    }

    // Validate JSON-RPC version
    if (![request[@"jsonrpc"] isEqualToString:@"2.0"]) {
        return [self makeErrorWithId:@"null" code:-32600 message:@"Invalid Request: missing or invalid jsonrpc version"];
    }

    NSString *method = request[@"method"] ?: @"";
    id rawId = request[@"id"];
    NSString *requestId = nil;
    if ([rawId isKindOfClass:[NSString class]]) {
        requestId = rawId;
    } else if ([rawId isKindOfClass:[NSNumber class]]) {
        requestId = [rawId stringValue];
    }

    NSDictionary *params = request[@"params"] ?: @{};

    // Handle notifications (no id)
    if (!requestId) {
        if ([method isEqualToString:@"notifications/initialized"]) {
            client.initialized = YES;
            NSLog(@"MCP Server: Client initialized");
        }
        return nil;  // Notifications don't get responses
    }

    // Handle requests
    if ([method isEqualToString:@"initialize"]) {
        return [self handleInitialize:requestId params:params];
    } else if ([method isEqualToString:@"tools/list"]) {
        return [self handleToolsList:requestId];
    } else if ([method isEqualToString:@"tools/call"]) {
        return [self handleToolsCall:requestId params:params];
    } else {
        return [self makeErrorWithId:requestId code:-32601 message:[@"Method not found: " stringByAppendingString:method]];
    }
}

#pragma mark - JSON-RPC Handlers

- (NSString *)handleInitialize:(NSString *)requestId params:(NSDictionary *)params {
    NSDictionary *result = @{
        @"protocolVersion": @"2025-03-26",
        @"capabilities": @{
            @"tools": @{@"listChanged": @NO}
        },
        @"serverInfo": @{
            @"name": @"xLights MCP Server",
            @"version": @"1.0.0"
        },
        @"instructions": @"xLights sequencing control server. Use tools/list to see available tools."
    };
    return [self makeResponseWithId:requestId result:result];
}

- (NSString *)handleToolsList:(NSString *)requestId {
    NSArray *tools = @[
        // Discovery tools
        @{@"name": @"xlights_listTimingTracks",
          @"description": @"List all timing tracks in the currently open sequence",
          @"inputSchema": @{@"type": @"object", @"properties": @{}, @"required": @[]}},

        @{@"name": @"xlights_getSequenceInfo",
          @"description": @"Get information about the currently open sequence including name, duration, frame rate, and media file",
          @"inputSchema": @{@"type": @"object", @"properties": @{}, @"required": @[]}},

        @{@"name": @"xlights_getModels",
          @"description": @"Get all models and model groups available in the current sequence",
          @"inputSchema": @{@"type": @"object", @"properties": @{}, @"required": @[]}},

        @{@"name": @"xlights_getTimingMarks",
          @"description": @"Get all timing marks (with start time, end time, and label) from a specific timing track",
          @"inputSchema": @{@"type": @"object",
                            @"properties": @{
                                @"trackName": @{@"type": @"string", @"description": @"The name of the timing track to get marks from"}
                            },
                            @"required": @[@"trackName"]}},

        @{@"name": @"xlights_listEffects",
          @"description": @"List all available effect types that can be added to models",
          @"inputSchema": @{@"type": @"object", @"properties": @{}, @"required": @[]}},

        // Effect CRUD
        @{@"name": @"xlights_addEffect",
          @"description": @"Add an effect to a model at a specific time range. Settings use prefixes: E_ for effect settings, C_ for color panel (C_SLIDER_Brightness, C_SLIDER_SparkleFrequency), T_ for layer blending (T_CHOICE_LayerMethod), B_ for buffer/render style (B_CHOICE_BufferStyle).",
          @"inputSchema": @{@"type": @"object",
                            @"properties": @{
                                @"modelName": @{@"type": @"string", @"description": @"The name of the model or group to add the effect to"},
                                @"effectName": @{@"type": @"string", @"description": @"The name of the effect type (e.g., 'Bars', 'Fire', 'Shockwave')"},
                                @"startTimeMs": @{@"type": @"integer", @"description": @"Start time in milliseconds"},
                                @"endTimeMs": @{@"type": @"integer", @"description": @"End time in milliseconds"},
                                @"layer": @{@"type": @"integer", @"description": @"Layer number (0-based, default 0)"},
                                @"settings": @{@"type": @"string", @"description": @"Effect settings as comma-separated key=value pairs (e.g., 'E_SLIDER_Speed=50,C_SLIDER_Brightness=100')"},
                                @"palette": @{@"type": @"string", @"description": @"Color palette settings as comma-separated values"}
                            },
                            @"required": @[@"modelName", @"effectName", @"startTimeMs", @"endTimeMs"]}},

        @{@"name": @"xlights_getEffects",
          @"description": @"Get all effects on a model, optionally filtered by time range",
          @"inputSchema": @{@"type": @"object",
                            @"properties": @{
                                @"modelName": @{@"type": @"string", @"description": @"The name of the model to get effects from"},
                                @"startTimeMs": @{@"type": @"integer", @"description": @"Optional start time filter in milliseconds"},
                                @"endTimeMs": @{@"type": @"integer", @"description": @"Optional end time filter in milliseconds"}
                            },
                            @"required": @[@"modelName"]}},

        @{@"name": @"xlights_deleteEffect",
          @"description": @"Delete an effect from a model. Specify either effectId or startTimeMs to identify the effect.",
          @"inputSchema": @{@"type": @"object",
                            @"properties": @{
                                @"modelName": @{@"type": @"string", @"description": @"The name of the model containing the effect"},
                                @"layer": @{@"type": @"integer", @"description": @"Layer number (0-based, default 0)"},
                                @"effectId": @{@"type": @"integer", @"description": @"The ID of the effect to delete (from getEffects)"},
                                @"startTimeMs": @{@"type": @"integer", @"description": @"Start time of the effect to delete (alternative to effectId)"}
                            },
                            @"required": @[@"modelName"]}},

        @{@"name": @"xlights_updateEffect",
          @"description": @"Update an existing effect's settings and/or palette. Specify either effectId or startTimeMs to identify the effect.",
          @"inputSchema": @{@"type": @"object",
                            @"properties": @{
                                @"modelName": @{@"type": @"string", @"description": @"The name of the model containing the effect"},
                                @"layer": @{@"type": @"integer", @"description": @"Layer number (0-based, default 0)"},
                                @"effectId": @{@"type": @"integer", @"description": @"The ID of the effect to update (from getEffects)"},
                                @"startTimeMs": @{@"type": @"integer", @"description": @"Start time of the effect to update (alternative to effectId)"},
                                @"settings": @{@"type": @"string", @"description": @"New effect settings (replaces existing settings)"},
                                @"palette": @{@"type": @"string", @"description": @"New color palette (replaces existing palette)"}
                            },
                            @"required": @[@"modelName"]}},

        @{@"name": @"xlights_copyEffects",
          @"description": @"Copy effects from one model/time range to another model/time. Effects are copied with their settings and colors preserved.",
          @"inputSchema": @{@"type": @"object",
                            @"properties": @{
                                @"sourceModelName": @{@"type": @"string", @"description": @"The name of the model to copy effects from"},
                                @"sourceStartTimeMs": @{@"type": @"integer", @"description": @"Start time of the range to copy from"},
                                @"sourceEndTimeMs": @{@"type": @"integer", @"description": @"End time of the range to copy from"},
                                @"targetModelName": @{@"type": @"string", @"description": @"The name of the model to copy effects to"},
                                @"targetStartTimeMs": @{@"type": @"integer", @"description": @"Start time where effects should be pasted"},
                                @"targetLayer": @{@"type": @"integer", @"description": @"Target layer number (0-based, default 0)"}
                            },
                            @"required": @[@"sourceModelName", @"sourceStartTimeMs", @"sourceEndTimeMs", @"targetModelName", @"targetStartTimeMs"]}},

        @{@"name": @"xlights_copyEffectsToTimingMarks",
          @"description": @"Copy effects to multiple timing marks based on a pattern. Great for repeating effects at beats, measures, or song sections.",
          @"inputSchema": @{@"type": @"object",
                            @"properties": @{
                                @"sourceModelName": @{@"type": @"string", @"description": @"The name of the model to copy effects from"},
                                @"sourceStartTimeMs": @{@"type": @"integer", @"description": @"Start time of the range to copy from"},
                                @"sourceEndTimeMs": @{@"type": @"integer", @"description": @"End time of the range to copy from"},
                                @"targetModelName": @{@"type": @"string", @"description": @"The name of the model to copy effects to"},
                                @"timingTrackName": @{@"type": @"string", @"description": @"The name of the timing track to use for placement"},
                                @"pattern": @{@"type": @"string", @"description": @"Pattern for selecting timing marks: 'all', 'even' (0,2,4...), 'odd' (1,3,5...), or a label to match"},
                                @"targetLayer": @{@"type": @"integer", @"description": @"Target layer number (0-based, default 0)"},
                                @"filterStartTimeMs": @{@"type": @"integer", @"description": @"Optional: Only include timing marks starting at or after this time"},
                                @"filterEndTimeMs": @{@"type": @"integer", @"description": @"Optional: Only include timing marks starting before this time"}
                            },
                            @"required": @[@"sourceModelName", @"sourceStartTimeMs", @"sourceEndTimeMs", @"targetModelName", @"timingTrackName", @"pattern"]}},

        // Presets
        @{@"name": @"xlights_listPresets",
          @"description": @"List all available effect presets that can be applied to models",
          @"inputSchema": @{@"type": @"object", @"properties": @{}, @"required": @[]}},

        @{@"name": @"xlights_applyPresetToTimingMarks",
          @"description": @"Apply an effect preset to timing marks on a model. Great for quickly applying saved effects to beats or song sections.",
          @"inputSchema": @{@"type": @"object",
                            @"properties": @{
                                @"presetName": @{@"type": @"string", @"description": @"The name of the preset to apply"},
                                @"targetModelName": @{@"type": @"string", @"description": @"The name of the model or group to apply the preset to"},
                                @"timingTrackName": @{@"type": @"string", @"description": @"The name of the timing track to use for placement"},
                                @"pattern": @{@"type": @"string", @"description": @"Pattern for selecting timing marks: 'all', 'even', 'odd', or a label to match"},
                                @"targetLayer": @{@"type": @"integer", @"description": @"Target layer number (0-based, default 0)"},
                                @"filterStartTimeMs": @{@"type": @"integer", @"description": @"Optional: start time filter"},
                                @"filterEndTimeMs": @{@"type": @"integer", @"description": @"Optional: end time filter"}
                            },
                            @"required": @[@"presetName", @"targetModelName", @"timingTrackName", @"pattern"]}},

        // Layers
        @{@"name": @"xlights_addLayer",
          @"description": @"Add a new effect layer to a model or group.",
          @"inputSchema": @{@"type": @"object",
                            @"properties": @{
                                @"modelName": @{@"type": @"string", @"description": @"The name of the model or group to add a layer to"}
                            },
                            @"required": @[@"modelName"]}},

        // Views
        @{@"name": @"xlights_getViewList",
          @"description": @"Get all available sequence views.",
          @"inputSchema": @{@"type": @"object", @"properties": @{}, @"required": @[]}},

        @{@"name": @"xlights_switchView",
          @"description": @"Switch to a different sequence view.",
          @"inputSchema": @{@"type": @"object",
                            @"properties": @{
                                @"viewName": @{@"type": @"string", @"description": @"The name of the view to switch to"}
                            },
                            @"required": @[@"viewName"]}},

        // Sequence creation
        @{@"name": @"xlights_createSequence",
          @"description": @"Create a new sequence with a media file.",
          @"inputSchema": @{@"type": @"object",
                            @"properties": @{
                                @"mediaFile": @{@"type": @"string", @"description": @"Full path to the media file (audio/video)"},
                                @"frameMS": @{@"type": @"integer", @"description": @"Frame timing in milliseconds (default 40 = 25fps)"}
                            },
                            @"required": @[@"mediaFile"]}},

        @{@"name": @"xlights_createTimingTrack",
          @"description": @"Create a new timing track with optional timing marks.",
          @"inputSchema": @{@"type": @"object",
                            @"properties": @{
                                @"trackName": @{@"type": @"string", @"description": @"Name of the timing track to create"},
                                @"marks": @{@"type": @"array",
                                            @"description": @"Array of timing marks, each with startMs, endMs, and label",
                                            @"items": @{@"type": @"object",
                                                         @"properties": @{
                                                             @"startMs": @{@"type": @"integer"},
                                                             @"endMs": @{@"type": @"integer"},
                                                             @"label": @{@"type": @"string"}
                                                         }}}
                            },
                            @"required": @[@"trackName"]}},

        @{@"name": @"xlights_saveSequence",
          @"description": @"Save the current sequence.",
          @"inputSchema": @{@"type": @"object",
                            @"properties": @{
                                @"filename": @{@"type": @"string", @"description": @"Full path for the sequence file (without extension). If not provided, saves to current location."}
                            },
                            @"required": @[]}},

        @{@"name": @"xlights_closeSequence",
          @"description": @"Close the current sequence.",
          @"inputSchema": @{@"type": @"object",
                            @"properties": @{
                                @"force": @{@"type": @"boolean", @"description": @"If true, closes without prompting to save (default: true)"}
                            },
                            @"required": @[]}},

        // Search and batch operations
        @{@"name": @"xlights_searchEffects",
          @"description": @"Search for effects across all models in the sequence. Filter by effect type, settings values, or time range.",
          @"inputSchema": @{@"type": @"object",
                            @"properties": @{
                                @"effectName": @{@"type": @"string", @"description": @"Filter by effect type name. Case-insensitive partial match."},
                                @"settingsFilter": @{@"type": @"string", @"description": @"Filter by settings as comma-separated key=value pairs."},
                                @"startTimeMs": @{@"type": @"integer", @"description": @"Only effects overlapping with range starting at this time"},
                                @"endTimeMs": @{@"type": @"integer", @"description": @"Only effects overlapping with range ending at this time"}
                            },
                            @"required": @[]}},

        @{@"name": @"xlights_batchUpdateEffects",
          @"description": @"Update multiple effects that match search criteria. Use this to change settings or palette across many effects at once.",
          @"inputSchema": @{@"type": @"object",
                            @"properties": @{
                                @"effectName": @{@"type": @"string", @"description": @"Filter by effect type name. Case-insensitive partial match."},
                                @"settingsFilter": @{@"type": @"string", @"description": @"Filter by settings as comma-separated key=value pairs."},
                                @"newSettings": @{@"type": @"string", @"description": @"New settings to apply (merged with existing)."},
                                @"newPalette": @{@"type": @"string", @"description": @"New palette to apply (replaces existing)."}
                            },
                            @"required": @[]}}
    ];

    NSDictionary *result = @{@"tools": tools};
    return [self makeResponseWithId:requestId result:result];
}

- (NSString *)handleToolsCall:(NSString *)requestId params:(NSDictionary *)params {
    NSString *toolName = params[@"name"] ?: @"";
    NSDictionary *arguments = params[@"arguments"] ?: @{};

    NSString *resultText = nil;
    BOOL isError = NO;

    // Dispatch to tool implementations
    if ([toolName isEqualToString:@"xlights_listTimingTracks"]) {
        resultText = [self toolListTimingTracks];
    } else if ([toolName isEqualToString:@"xlights_getSequenceInfo"]) {
        resultText = [self toolGetSequenceInfo];
    } else if ([toolName isEqualToString:@"xlights_getModels"]) {
        resultText = [self toolGetModels];
    } else if ([toolName isEqualToString:@"xlights_getTimingMarks"]) {
        NSString *trackName = arguments[@"trackName"] ?: @"";
        if (trackName.length == 0) {
            resultText = @"Error: trackName parameter is required";
            isError = YES;
        } else {
            resultText = [self toolGetTimingMarks:trackName];
        }
    } else if ([toolName isEqualToString:@"xlights_listEffects"]) {
        resultText = [self toolListEffects];
    } else if ([toolName isEqualToString:@"xlights_addEffect"]) {
        resultText = [self toolAddEffect:arguments];
        isError = [resultText hasPrefix:@"Error:"];
    } else if ([toolName isEqualToString:@"xlights_getEffects"]) {
        resultText = [self toolGetEffects:arguments];
        isError = [resultText hasPrefix:@"Error:"];
    } else if ([toolName isEqualToString:@"xlights_deleteEffect"]) {
        resultText = [self toolDeleteEffect:arguments];
        isError = [resultText hasPrefix:@"Error:"];
    } else if ([toolName isEqualToString:@"xlights_updateEffect"]) {
        resultText = [self toolUpdateEffect:arguments];
        isError = [resultText hasPrefix:@"Error:"];
    } else if ([toolName isEqualToString:@"xlights_copyEffects"]) {
        resultText = [self toolCopyEffects:arguments];
        isError = [resultText hasPrefix:@"Error:"];
    } else if ([toolName isEqualToString:@"xlights_copyEffectsToTimingMarks"]) {
        resultText = [self toolCopyEffectsToTimingMarks:arguments];
        isError = [resultText hasPrefix:@"Error:"];
    } else if ([toolName isEqualToString:@"xlights_listPresets"]) {
        resultText = [self toolListPresets];
        isError = [resultText hasPrefix:@"Error:"];
    } else if ([toolName isEqualToString:@"xlights_applyPresetToTimingMarks"]) {
        resultText = [self toolApplyPresetToTimingMarks:arguments];
        isError = [resultText hasPrefix:@"Error:"];
    } else if ([toolName isEqualToString:@"xlights_addLayer"]) {
        NSString *modelName = arguments[@"modelName"] ?: @"";
        if (modelName.length == 0) {
            resultText = @"Error: modelName is required";
            isError = YES;
        } else {
            resultText = [self toolAddLayer:modelName];
            isError = [resultText hasPrefix:@"Error:"];
        }
    } else if ([toolName isEqualToString:@"xlights_getViewList"]) {
        resultText = [self toolGetViewList];
        isError = [resultText hasPrefix:@"Error:"];
    } else if ([toolName isEqualToString:@"xlights_switchView"]) {
        NSString *viewName = arguments[@"viewName"] ?: @"";
        if (viewName.length == 0) {
            resultText = @"Error: viewName is required";
            isError = YES;
        } else {
            resultText = [self toolSwitchView:viewName];
            isError = [resultText hasPrefix:@"Error:"];
        }
    } else if ([toolName isEqualToString:@"xlights_createSequence"]) {
        resultText = [self toolCreateSequence:arguments];
        isError = [resultText hasPrefix:@"Error:"];
    } else if ([toolName isEqualToString:@"xlights_createTimingTrack"]) {
        resultText = [self toolCreateTimingTrack:arguments];
        isError = [resultText hasPrefix:@"Error:"];
    } else if ([toolName isEqualToString:@"xlights_saveSequence"]) {
        resultText = [self toolSaveSequence:arguments];
        isError = [resultText hasPrefix:@"Error:"];
    } else if ([toolName isEqualToString:@"xlights_closeSequence"]) {
        resultText = [self toolCloseSequence:arguments];
        isError = [resultText hasPrefix:@"Error:"];
    } else if ([toolName isEqualToString:@"xlights_searchEffects"]) {
        resultText = [self toolSearchEffects:arguments];
        isError = [resultText hasPrefix:@"Error:"];
    } else if ([toolName isEqualToString:@"xlights_batchUpdateEffects"]) {
        resultText = [self toolBatchUpdateEffects:arguments];
        isError = [resultText hasPrefix:@"Error:"];
    } else {
        resultText = [NSString stringWithFormat:@"Unknown tool: %@", toolName];
        isError = YES;
    }

    NSDictionary *result = @{
        @"content": @[@{@"type": @"text", @"text": resultText ?: @""}],
        @"isError": @(isError)
    };
    return [self makeResponseWithId:requestId result:result];
}

#pragma mark - Tool Implementations: Discovery

- (NSString *)toolListTimingTracks {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";
    if (![bridge isSequenceLoaded]) return @"No sequence is currently open";

    NSArray<NSDictionary *> *tracks = [bridge getTimingTracks];
    if (!tracks || tracks.count == 0) {
        return @"No timing tracks found in the current sequence";
    }

    NSDictionary *response = @{
        @"timingTracks": tracks,
        @"count": @(tracks.count)
    };
    return [self jsonStringFromDict:response];
}

- (NSString *)toolGetSequenceInfo {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";
    if (![bridge isSequenceLoaded]) return @"No sequence is currently open";

    NSDictionary *info = [bridge getSequenceInfo];
    if (!info) return @"Error: Could not get sequence info";

    return [self jsonStringFromDict:info];
}

- (NSString *)toolGetModels {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";

    NSArray<NSString *> *modelNames = [bridge getModelNamesExcludingGroups];
    NSArray<NSString *> *groupNames = [bridge getGroupNames];

    NSMutableArray *models = [NSMutableArray array];
    for (NSString *name in modelNames) {
        NSDictionary *info = [bridge getModelInfo:name];
        if (info) {
            [models addObject:@{
                @"name": name,
                @"displayAs": info[@"displayAs"] ?: @"",
                @"nodeCount": info[@"nodeCount"] ?: @0,
                @"channelCount": info[@"channelCount"] ?: @0
            }];
        }
    }

    NSMutableArray *groups = [NSMutableArray array];
    for (NSString *name in groupNames) {
        NSDictionary *groupInfo = [bridge getModelGroup:name];
        NSArray *members = groupInfo[@"modelNames"] ?: @[];
        [groups addObject:@{
            @"name": name,
            @"modelCount": @(members.count)
        }];
    }

    NSDictionary *response = @{
        @"models": models,
        @"modelCount": @(models.count),
        @"groups": groups,
        @"groupCount": @(groups.count)
    };
    return [self jsonStringFromDict:response];
}

- (NSString *)toolGetTimingMarks:(NSString *)trackName {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";
    if (![bridge isSequenceLoaded]) return @"Error: No sequence is currently open";

    // Get timing tracks to find the one we want and its layer count
    NSArray<NSDictionary *> *tracks = [bridge getTimingTracks];
    NSDictionary *targetTrack = nil;
    for (NSDictionary *track in tracks) {
        if ([track[@"name"] isEqualToString:trackName]) {
            targetTrack = track;
            break;
        }
    }

    if (!targetTrack) {
        return [NSString stringWithFormat:@"Error: Timing track '%@' not found", trackName];
    }

    NSInteger layerCount = [targetTrack[@"layerCount"] integerValue];
    NSMutableArray *marks = [NSMutableArray array];

    for (NSInteger layer = 0; layer < layerCount; layer++) {
        NSArray<NSDictionary *> *layerMarks = [bridge getTimingMarks:trackName layer:layer];
        for (NSDictionary *mark in layerMarks) {
            [marks addObject:@{
                @"startTimeMs": mark[@"startTimeMS"] ?: @0,
                @"endTimeMs": mark[@"endTimeMS"] ?: @0,
                @"label": mark[@"label"] ?: @"",
                @"layer": @(layer)
            }];
        }
    }

    NSDictionary *response = @{
        @"trackName": trackName,
        @"marks": marks,
        @"markCount": @(marks.count)
    };
    return [self jsonStringFromDict:response];
}

- (NSString *)toolListEffects {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";

    NSArray<NSString *> *effectTypes = [bridge getEffectTypes];
    NSMutableArray *effects = [NSMutableArray array];

    for (NSUInteger i = 0; i < effectTypes.count; i++) {
        [effects addObject:@{
            @"name": effectTypes[i],
            @"id": @(i)
        }];
    }

    NSDictionary *response = @{
        @"effects": effects,
        @"count": @(effects.count)
    };
    return [self jsonStringFromDict:response];
}

#pragma mark - Tool Implementations: Effect CRUD

- (NSString *)toolAddEffect:(NSDictionary *)arguments {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";
    if (![bridge isSequenceLoaded]) return @"Error: No sequence is currently open";

    NSString *modelName = arguments[@"modelName"] ?: @"";
    NSString *effectName = arguments[@"effectName"] ?: @"";
    NSInteger startTimeMs = [arguments[@"startTimeMs"] integerValue];
    NSInteger endTimeMs = [arguments[@"endTimeMs"] integerValue];
    NSInteger layer = [arguments[@"layer"] integerValue];
    NSString *settings = arguments[@"settings"] ?: @"";
    NSString *palette = arguments[@"palette"] ?: @"";

    if (modelName.length == 0) return @"Error: modelName parameter is required";
    if (effectName.length == 0) return @"Error: effectName parameter is required";
    if (endTimeMs <= startTimeMs) return @"Error: endTimeMs must be greater than startTimeMs";

    if (![bridge hasModel:modelName]) {
        return [NSString stringWithFormat:@"Error: Model or group '%@' not found", modelName];
    }

    // Ensure enough layers exist
    NSInteger currentLayers = [bridge getLayerCount:modelName];
    while (currentLayers <= layer) {
        [bridge addLayer:modelName];
        currentLayers++;
    }

    // Create the effect
    NSInteger effectId = [bridge createEffect:modelName layer:layer effectType:effectName
                                  startTimeMS:startTimeMs endTimeMS:endTimeMs];
    if (effectId < 0) {
        return @"Error: Failed to add effect. Time range may overlap with existing effect.";
    }

    // Apply settings if provided
    if (settings.length > 0) {
        [bridge setEffectSettings:effectId settings:settings];
    }

    // Apply palette if provided
    if (palette.length > 0) {
        [bridge setEffectPalette:effectId palette:palette];
    } else {
        // Default white palette
        [bridge setEffectPalette:effectId palette:@"C_BUTTON_Palette1=#FFFFFF,C_CHECKBOX_Palette1=1,C_BUTTON_Palette2=#000000,C_CHECKBOX_Palette2=0"];
    }

    NSDictionary *response = @{
        @"success": @YES,
        @"effectId": @(effectId),
        @"modelName": modelName,
        @"effectName": effectName,
        @"startTimeMs": @(startTimeMs),
        @"endTimeMs": @(endTimeMs),
        @"layer": @(layer)
    };
    return [self jsonStringFromDict:response];
}

- (NSString *)toolGetEffects:(NSDictionary *)arguments {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";
    if (![bridge isSequenceLoaded]) return @"Error: No sequence is currently open";

    NSString *modelName = arguments[@"modelName"] ?: @"";
    if (modelName.length == 0) return @"Error: modelName parameter is required";

    if (![bridge hasModel:modelName]) {
        return [NSString stringWithFormat:@"Error: Model or group '%@' not found in sequence", modelName];
    }

    NSInteger filterStart = arguments[@"startTimeMs"] ? [arguments[@"startTimeMs"] integerValue] : -1;
    NSInteger filterEnd = arguments[@"endTimeMs"] ? [arguments[@"endTimeMs"] integerValue] : -1;

    NSArray<NSDictionary *> *allEffects = [bridge getEffectsForModel:modelName];
    NSMutableArray *filteredEffects = [NSMutableArray array];

    for (NSDictionary *effect in allEffects) {
        NSInteger effectStart = [effect[@"startTimeMS"] integerValue];
        NSInteger effectEnd = [effect[@"endTimeMS"] integerValue];

        // Apply time filter
        if (filterStart >= 0 && filterEnd >= 0) {
            if (effectEnd <= filterStart || effectStart >= filterEnd) {
                continue;
            }
        }

        NSString *settingsStr = effect[@"settings"] ?: @"";
        NSString *paletteStr = effect[@"palette"] ?: @"";

        [filteredEffects addObject:@{
            @"id": effect[@"id"] ?: @(-1),
            @"name": effect[@"effectType"] ?: @"",
            @"startTimeMs": @(effectStart),
            @"endTimeMs": @(effectEnd),
            @"layer": effect[@"layerIndex"] ?: @0,
            @"settings": settingsStr,
            @"palette": paletteStr
        }];
    }

    NSInteger layerCount = [bridge getLayerCount:modelName];

    NSDictionary *response = @{
        @"modelName": modelName,
        @"effects": filteredEffects,
        @"effectCount": @(filteredEffects.count),
        @"layerCount": @(layerCount)
    };
    return [self jsonStringFromDict:response];
}

- (NSString *)toolDeleteEffect:(NSDictionary *)arguments {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";
    if (![bridge isSequenceLoaded]) return @"Error: No sequence is currently open";

    NSString *modelName = arguments[@"modelName"] ?: @"";
    NSInteger layer = [arguments[@"layer"] integerValue];
    NSInteger effectId = arguments[@"effectId"] ? [arguments[@"effectId"] integerValue] : -1;
    NSInteger startTimeMs = arguments[@"startTimeMs"] ? [arguments[@"startTimeMs"] integerValue] : -1;

    if (modelName.length == 0) return @"Error: modelName parameter is required";
    if (effectId < 0 && startTimeMs < 0) return @"Error: Either effectId or startTimeMs must be specified";

    // If we have an effectId, use it directly
    if (effectId >= 0) {
        NSDictionary *effectInfo = [bridge getEffect:effectId];
        if (!effectInfo) return @"Error: Effect not found";

        NSString *deletedName = effectInfo[@"effectType"] ?: @"";
        NSInteger deletedStart = [effectInfo[@"startTimeMS"] integerValue];
        NSInteger deletedEnd = [effectInfo[@"endTimeMS"] integerValue];

        BOOL success = [bridge deleteEffect:effectId];
        if (!success) return @"Error: Failed to delete effect";

        NSDictionary *response = @{
            @"success": @YES,
            @"deletedEffect": @{
                @"id": @(effectId),
                @"name": deletedName,
                @"startTimeMs": @(deletedStart),
                @"endTimeMs": @(deletedEnd),
                @"layer": @(layer)
            },
            @"modelName": modelName
        };
        return [self jsonStringFromDict:response];
    }

    // Find by start time on the specified layer
    NSArray<NSDictionary *> *layerEffects = [bridge getEffectsForLayer:modelName layer:layer];
    for (NSDictionary *effect in layerEffects) {
        if ([effect[@"startTimeMS"] integerValue] == startTimeMs) {
            NSInteger eid = [effect[@"id"] integerValue];
            NSString *deletedName = effect[@"effectType"] ?: @"";
            NSInteger deletedEnd = [effect[@"endTimeMS"] integerValue];

            BOOL success = [bridge deleteEffect:eid];
            if (!success) return @"Error: Failed to delete effect";

            NSDictionary *response = @{
                @"success": @YES,
                @"deletedEffect": @{
                    @"id": @(eid),
                    @"name": deletedName,
                    @"startTimeMs": @(startTimeMs),
                    @"endTimeMs": @(deletedEnd),
                    @"layer": @(layer)
                },
                @"modelName": modelName
            };
            return [self jsonStringFromDict:response];
        }
    }

    return @"Error: Effect not found";
}

- (NSString *)toolUpdateEffect:(NSDictionary *)arguments {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";
    if (![bridge isSequenceLoaded]) return @"Error: No sequence is currently open";

    NSString *modelName = arguments[@"modelName"] ?: @"";
    NSInteger layer = [arguments[@"layer"] integerValue];
    NSInteger effectId = arguments[@"effectId"] ? [arguments[@"effectId"] integerValue] : -1;
    NSInteger startTimeMs = arguments[@"startTimeMs"] ? [arguments[@"startTimeMs"] integerValue] : -1;
    NSString *settings = arguments[@"settings"] ?: @"";
    NSString *palette = arguments[@"palette"] ?: @"";

    if (modelName.length == 0) return @"Error: modelName parameter is required";
    if (effectId < 0 && startTimeMs < 0) return @"Error: Either effectId or startTimeMs must be specified";
    if (settings.length == 0 && palette.length == 0) return @"Error: Either settings or palette must be specified";

    // Resolve effectId from startTimeMs if needed
    if (effectId < 0 && startTimeMs >= 0) {
        NSArray<NSDictionary *> *layerEffects = [bridge getEffectsForLayer:modelName layer:layer];
        for (NSDictionary *effect in layerEffects) {
            if ([effect[@"startTimeMS"] integerValue] == startTimeMs) {
                effectId = [effect[@"id"] integerValue];
                break;
            }
        }
    }

    if (effectId < 0) return @"Error: Effect not found";

    NSDictionary *effectInfo = [bridge getEffect:effectId];
    if (!effectInfo) return @"Error: Effect not found";

    if (settings.length > 0) {
        [bridge setEffectSettings:effectId settings:settings];
    }
    if (palette.length > 0) {
        [bridge setEffectPalette:effectId palette:palette];
    }

    // Re-read effect info after update
    effectInfo = [bridge getEffect:effectId];

    NSDictionary *response = @{
        @"success": @YES,
        @"effectId": @(effectId),
        @"effectName": effectInfo[@"effectType"] ?: @"",
        @"modelName": modelName,
        @"layer": @(layer),
        @"newSettings": effectInfo[@"settings"] ?: @"",
        @"newPalette": effectInfo[@"palette"] ?: @""
    };
    return [self jsonStringFromDict:response];
}

- (NSString *)toolCopyEffects:(NSDictionary *)arguments {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";
    if (![bridge isSequenceLoaded]) return @"Error: No sequence is currently open";

    NSString *sourceModelName = arguments[@"sourceModelName"] ?: @"";
    NSInteger sourceStartTimeMs = [arguments[@"sourceStartTimeMs"] integerValue];
    NSInteger sourceEndTimeMs = [arguments[@"sourceEndTimeMs"] integerValue];
    NSString *targetModelName = arguments[@"targetModelName"] ?: @"";
    NSInteger targetStartTimeMs = [arguments[@"targetStartTimeMs"] integerValue];
    NSInteger targetLayer = [arguments[@"targetLayer"] integerValue];

    if (sourceModelName.length == 0 || targetModelName.length == 0)
        return @"Error: sourceModelName and targetModelName are required";

    // Collect source effects
    NSArray<NSDictionary *> *sourceEffects = [bridge getEffectsForModel:sourceModelName];
    NSMutableArray<NSDictionary *> *effectsToCopy = [NSMutableArray array];

    for (NSDictionary *effect in sourceEffects) {
        NSInteger effectStart = [effect[@"startTimeMS"] integerValue];
        NSInteger effectEnd = [effect[@"endTimeMS"] integerValue];

        if (effectStart >= sourceStartTimeMs && effectEnd <= sourceEndTimeMs) {
            [effectsToCopy addObject:@{
                @"effectType": effect[@"effectType"] ?: @"",
                @"settings": effect[@"settings"] ?: @"",
                @"palette": effect[@"palette"] ?: @"",
                @"relativeStart": @(effectStart - sourceStartTimeMs),
                @"relativeEnd": @(effectEnd - sourceStartTimeMs)
            }];
        }
    }

    if (effectsToCopy.count == 0) return @"Error: No effects found in the specified source time range";

    // Ensure target layer exists
    NSInteger currentLayers = [bridge getLayerCount:targetModelName];
    while (currentLayers <= targetLayer) {
        [bridge addLayer:targetModelName];
        currentLayers++;
    }

    // Copy effects
    NSInteger copiedCount = 0;
    NSMutableArray *copiedEffects = [NSMutableArray array];

    for (NSDictionary *effectData in effectsToCopy) {
        NSInteger newStart = targetStartTimeMs + [effectData[@"relativeStart"] integerValue];
        NSInteger newEnd = targetStartTimeMs + [effectData[@"relativeEnd"] integerValue];

        NSInteger newId = [bridge createEffect:targetModelName layer:targetLayer
                                    effectType:effectData[@"effectType"]
                                   startTimeMS:newStart endTimeMS:newEnd];
        if (newId >= 0) {
            NSString *settings = effectData[@"settings"];
            NSString *palette = effectData[@"palette"];
            if (settings.length > 0) [bridge setEffectSettings:newId settings:settings];
            if (palette.length > 0) [bridge setEffectPalette:newId palette:palette];

            copiedCount++;
            [copiedEffects addObject:@{
                @"name": effectData[@"effectType"],
                @"startTimeMs": @(newStart),
                @"endTimeMs": @(newEnd)
            }];
        }
    }

    NSDictionary *response = @{
        @"success": @YES,
        @"copiedCount": @(copiedCount),
        @"sourceModelName": sourceModelName,
        @"targetModelName": targetModelName,
        @"targetStartTimeMs": @(targetStartTimeMs),
        @"targetLayer": @(targetLayer),
        @"effects": copiedEffects
    };
    return [self jsonStringFromDict:response];
}

- (NSString *)toolCopyEffectsToTimingMarks:(NSDictionary *)arguments {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";
    if (![bridge isSequenceLoaded]) return @"Error: No sequence is currently open";

    NSString *sourceModelName = arguments[@"sourceModelName"] ?: @"";
    NSInteger sourceStartTimeMs = [arguments[@"sourceStartTimeMs"] integerValue];
    NSInteger sourceEndTimeMs = [arguments[@"sourceEndTimeMs"] integerValue];
    NSString *targetModelName = arguments[@"targetModelName"] ?: @"";
    NSString *timingTrackName = arguments[@"timingTrackName"] ?: @"";
    NSString *pattern = arguments[@"pattern"] ?: @"";
    NSInteger targetLayer = [arguments[@"targetLayer"] integerValue];
    NSInteger filterStartTimeMs = arguments[@"filterStartTimeMs"] ? [arguments[@"filterStartTimeMs"] integerValue] : -1;
    NSInteger filterEndTimeMs = arguments[@"filterEndTimeMs"] ? [arguments[@"filterEndTimeMs"] integerValue] : -1;

    if (sourceModelName.length == 0 || targetModelName.length == 0)
        return @"Error: sourceModelName and targetModelName are required";
    if (timingTrackName.length == 0 || pattern.length == 0)
        return @"Error: timingTrackName and pattern are required";

    // Collect source effects
    NSArray<NSDictionary *> *sourceEffects = [bridge getEffectsForModel:sourceModelName];
    NSMutableArray<NSDictionary *> *effectsToCopy = [NSMutableArray array];

    for (NSDictionary *effect in sourceEffects) {
        NSInteger effectStart = [effect[@"startTimeMS"] integerValue];
        NSInteger effectEnd = [effect[@"endTimeMS"] integerValue];

        if (effectStart >= sourceStartTimeMs && effectEnd <= sourceEndTimeMs) {
            [effectsToCopy addObject:@{
                @"effectType": effect[@"effectType"] ?: @"",
                @"settings": effect[@"settings"] ?: @"",
                @"palette": effect[@"palette"] ?: @"",
                @"relativeStart": @(effectStart - sourceStartTimeMs),
                @"relativeEnd": @(effectEnd - sourceStartTimeMs)
            }];
        }
    }

    if (effectsToCopy.count == 0) return @"Error: No effects found in the specified source time range";

    // Collect timing marks
    NSArray *targetTimingMarks = [self collectTimingMarks:timingTrackName
                                                 pattern:pattern
                                          filterStartMs:filterStartTimeMs
                                            filterEndMs:filterEndTimeMs];
    if (!targetTimingMarks) return [NSString stringWithFormat:@"Error: Timing track '%@' not found", timingTrackName];
    if (targetTimingMarks.count == 0)
        return [NSString stringWithFormat:@"Error: No timing marks matched the pattern '%@'", pattern];

    // Ensure target layer exists
    NSInteger currentLayers = [bridge getLayerCount:targetModelName];
    while (currentLayers <= targetLayer) {
        [bridge addLayer:targetModelName];
        currentLayers++;
    }

    // Copy to each timing mark
    NSInteger totalCopied = 0;
    NSMutableArray *placementInfo = [NSMutableArray array];

    for (NSDictionary *timingMark in targetTimingMarks) {
        NSInteger markStart = [timingMark[@"startTimeMs"] integerValue];
        NSInteger copiedToMark = 0;

        for (NSDictionary *effectData in effectsToCopy) {
            NSInteger newStart = markStart + [effectData[@"relativeStart"] integerValue];
            NSInteger newEnd = markStart + [effectData[@"relativeEnd"] integerValue];

            NSInteger newId = [bridge createEffect:targetModelName layer:targetLayer
                                        effectType:effectData[@"effectType"]
                                       startTimeMS:newStart endTimeMS:newEnd];
            if (newId >= 0) {
                NSString *settings = effectData[@"settings"];
                NSString *pal = effectData[@"palette"];
                if (settings.length > 0) [bridge setEffectSettings:newId settings:settings];
                if (pal.length > 0) [bridge setEffectPalette:newId palette:pal];
                copiedToMark++;
                totalCopied++;
            }
        }

        [placementInfo addObject:@{
            @"timingMarkStartMs": @(markStart),
            @"effectsCopied": @(copiedToMark)
        }];
    }

    NSMutableDictionary *response = [@{
        @"success": @YES,
        @"totalCopied": @(totalCopied),
        @"timingMarksUsed": @(targetTimingMarks.count),
        @"sourceModelName": sourceModelName,
        @"targetModelName": targetModelName,
        @"timingTrackName": timingTrackName,
        @"pattern": pattern,
        @"targetLayer": @(targetLayer),
        @"placements": placementInfo
    } mutableCopy];

    if (filterStartTimeMs >= 0) response[@"filterStartTimeMs"] = @(filterStartTimeMs);
    if (filterEndTimeMs >= 0) response[@"filterEndTimeMs"] = @(filterEndTimeMs);

    return [self jsonStringFromDict:response];
}

#pragma mark - Tool Implementations: Presets

- (NSString *)toolListPresets {
    XLEffectPresetsWindowController *presets = self.presetsController;
    if (!presets) {
        return [self jsonStringFromDict:@{@"count": @0, @"presets": @[], @"note": @"Preset system not available"}];
    }

    NSArray<NSString *> *presetNames = [presets presetNamesForEffectType:nil];
    NSDictionary *response = @{
        @"count": @(presetNames.count),
        @"presets": presetNames ?: @[]
    };
    return [self jsonStringFromDict:response];
}

- (NSString *)toolApplyPresetToTimingMarks:(NSDictionary *)arguments {
    XLEngineBridge *bridge = self.engineBridge;
    XLEffectPresetsWindowController *presets = self.presetsController;
    if (!bridge) return @"Error: Engine not available";
    if (!presets) return @"Error: Preset system not available";
    if (![bridge isSequenceLoaded]) return @"Error: No sequence is currently open";

    NSString *presetName = arguments[@"presetName"] ?: @"";
    NSString *targetModelName = arguments[@"targetModelName"] ?: @"";
    NSString *timingTrackName = arguments[@"timingTrackName"] ?: @"";
    NSString *pattern = arguments[@"pattern"] ?: @"";
    NSInteger targetLayer = [arguments[@"targetLayer"] integerValue];
    NSInteger filterStartTimeMs = arguments[@"filterStartTimeMs"] ? [arguments[@"filterStartTimeMs"] integerValue] : -1;
    NSInteger filterEndTimeMs = arguments[@"filterEndTimeMs"] ? [arguments[@"filterEndTimeMs"] integerValue] : -1;

    if (presetName.length == 0 || targetModelName.length == 0)
        return @"Error: presetName and targetModelName are required";
    if (timingTrackName.length == 0 || pattern.length == 0)
        return @"Error: timingTrackName and pattern are required";

    // Collect timing marks
    NSArray *targetTimingMarks = [self collectTimingMarks:timingTrackName
                                                 pattern:pattern
                                          filterStartMs:filterStartTimeMs
                                            filterEndMs:filterEndTimeMs];
    if (!targetTimingMarks) return [NSString stringWithFormat:@"Error: Timing track '%@' not found", timingTrackName];
    if (targetTimingMarks.count == 0)
        return [NSString stringWithFormat:@"Error: No timing marks matched the pattern '%@'", pattern];

    // Ensure target layer exists
    NSInteger currentLayers = [bridge getLayerCount:targetModelName];
    while (currentLayers <= targetLayer) {
        [bridge addLayer:targetModelName];
        currentLayers++;
    }

    // For each timing mark, create an effect and apply the preset to it
    NSInteger totalApplied = 0;
    NSMutableArray *placementInfo = [NSMutableArray array];

    for (NSDictionary *timingMark in targetTimingMarks) {
        NSInteger markStart = [timingMark[@"startTimeMs"] integerValue];
        NSInteger markEnd = [timingMark[@"endTimeMs"] integerValue];

        // Create a temporary "On" effect at the timing mark location
        NSInteger tempId = [bridge createEffect:targetModelName layer:targetLayer
                                     effectType:@"On"
                                    startTimeMS:markStart endTimeMS:markEnd];
        if (tempId >= 0) {
            BOOL applied = [presets applyPreset:presetName toEffect:tempId];
            if (applied) {
                totalApplied++;
                [placementInfo addObject:@{
                    @"timingMarkStartMs": @(markStart),
                    @"effectsApplied": @1
                }];
            } else {
                // Failed to apply preset, clean up
                [bridge deleteEffect:tempId];
                [placementInfo addObject:@{
                    @"timingMarkStartMs": @(markStart),
                    @"effectsApplied": @0
                }];
            }
        }
    }

    NSMutableDictionary *response = [@{
        @"success": @YES,
        @"totalApplied": @(totalApplied),
        @"timingMarksUsed": @(targetTimingMarks.count),
        @"presetName": presetName,
        @"targetModelName": targetModelName,
        @"timingTrackName": timingTrackName,
        @"pattern": pattern,
        @"targetLayer": @(targetLayer),
        @"placements": placementInfo
    } mutableCopy];

    if (filterStartTimeMs >= 0) response[@"filterStartTimeMs"] = @(filterStartTimeMs);
    if (filterEndTimeMs >= 0) response[@"filterEndTimeMs"] = @(filterEndTimeMs);

    return [self jsonStringFromDict:response];
}

#pragma mark - Tool Implementations: Layers

- (NSString *)toolAddLayer:(NSString *)modelName {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";
    if (![bridge isSequenceLoaded]) return @"Error: No sequence is currently open";

    if (![bridge hasModel:modelName]) {
        return [NSString stringWithFormat:@"Error: Model or group '%@' not found", modelName];
    }

    NSInteger previousLayerCount = [bridge getLayerCount:modelName];
    NSInteger newLayerIndex = [bridge addLayer:modelName];

    if (newLayerIndex < 0) return @"Error: Failed to add layer";

    NSDictionary *response = @{
        @"success": @YES,
        @"modelName": modelName,
        @"previousLayerCount": @(previousLayerCount),
        @"newLayerCount": @(newLayerIndex + 1),
        @"newLayerIndex": @(newLayerIndex)
    };
    return [self jsonStringFromDict:response];
}

#pragma mark - Tool Implementations: Views

- (NSString *)toolGetViewList {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";
    if (![bridge isSequenceLoaded]) return @"Error: No sequence is currently open";

    NSArray<NSString *> *viewNames = [bridge getViewNames];
    NSString *currentView = [bridge getCurrentViewName];
    NSInteger currentIndex = [bridge getCurrentViewIndex];

    NSMutableArray *viewList = [NSMutableArray array];
    for (NSUInteger i = 0; i < viewNames.count; i++) {
        [viewList addObject:@{
            @"name": viewNames[i],
            @"index": @(i),
            @"isCurrent": @([viewNames[i] isEqualToString:currentView])
        }];
    }

    NSDictionary *response = @{
        @"success": @YES,
        @"viewCount": @(viewNames.count),
        @"currentView": currentView ?: @"",
        @"currentViewIndex": @(currentIndex),
        @"views": viewList
    };
    return [self jsonStringFromDict:response];
}

- (NSString *)toolSwitchView:(NSString *)viewName {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";
    if (![bridge isSequenceLoaded]) return @"Error: No sequence is currently open";

    NSString *previousView = [bridge getCurrentViewName];
    NSInteger previousIndex = [bridge getCurrentViewIndex];

    BOOL success = [bridge setCurrentView:viewName];
    if (!success) {
        return [NSString stringWithFormat:@"Error: View '%@' not found", viewName];
    }

    NSString *newView = [bridge getCurrentViewName];
    NSInteger newIndex = [bridge getCurrentViewIndex];

    NSDictionary *response = @{
        @"success": @YES,
        @"previousView": previousView ?: @"",
        @"previousViewIndex": @(previousIndex),
        @"currentView": newView ?: @"",
        @"currentViewIndex": @(newIndex)
    };
    return [self jsonStringFromDict:response];
}

#pragma mark - Tool Implementations: Sequence Creation

- (NSString *)toolCreateSequence:(NSDictionary *)arguments {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";

    NSString *mediaFile = arguments[@"mediaFile"] ?: @"";
    NSInteger frameMS = arguments[@"frameMS"] ? [arguments[@"frameMS"] integerValue] : 40;

    if (mediaFile.length == 0) return @"Error: mediaFile is required";
    if (![[NSFileManager defaultManager] fileExistsAtPath:mediaFile]) {
        return [NSString stringWithFormat:@"Error: Media file not found: %@", mediaFile];
    }
    if (frameMS <= 0) frameMS = 40;

    BOOL success = [bridge createSequence:[[mediaFile lastPathComponent] stringByDeletingPathExtension]
                               durationMS:0  // Use media duration
                                  frameMS:frameMS
                                mediaFile:mediaFile];

    if (!success) return @"Error: Failed to create sequence";

    NSDictionary *info = [bridge getSequenceInfo];
    NSDictionary *response = @{
        @"success": @YES,
        @"sequenceName": info[@"name"] ?: @"",
        @"mediaFile": mediaFile,
        @"durationMs": info[@"durationMS"] ?: @0,
        @"frameMs": @(frameMS),
        @"framesPerSecond": @(1000 / frameMS)
    };
    return [self jsonStringFromDict:response];
}

- (NSString *)toolCreateTimingTrack:(NSDictionary *)arguments {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";
    if (![bridge isSequenceLoaded]) return @"Error: No sequence is currently open";

    NSString *trackName = arguments[@"trackName"] ?: @"";
    if (trackName.length == 0) return @"Error: trackName is required";

    // Check if track already exists
    NSArray<NSDictionary *> *existingTracks = [bridge getTimingTracks];
    for (NSDictionary *track in existingTracks) {
        if ([track[@"name"] isEqualToString:trackName]) {
            return [NSString stringWithFormat:@"Error: Timing track '%@' already exists", trackName];
        }
    }

    BOOL success = [bridge createTimingTrack:trackName];
    if (!success) return @"Error: Failed to create timing track";

    // Add timing marks if provided
    NSArray *marks = arguments[@"marks"];
    NSInteger markCount = 0;
    NSMutableArray *addedMarks = [NSMutableArray array];

    if ([marks isKindOfClass:[NSArray class]] && marks.count > 0) {
        for (NSDictionary *mark in marks) {
            NSInteger startMs = [mark[@"startMs"] integerValue];
            NSInteger endMs = [mark[@"endMs"] integerValue];
            NSString *label = mark[@"label"] ?: @"";

            NSInteger markId = [bridge createTimingMark:trackName layer:0
                                            startTimeMS:startMs endTimeMS:endMs label:label];
            if (markId >= 0) {
                markCount++;
                [addedMarks addObject:@{
                    @"startMs": @(startMs),
                    @"endMs": @(endMs),
                    @"label": label
                }];
            }
        }
    }

    NSMutableDictionary *response = [@{
        @"success": @YES,
        @"trackName": trackName,
        @"markCount": @(markCount)
    } mutableCopy];

    if (addedMarks.count > 0) {
        response[@"marks"] = addedMarks;
    }

    return [self jsonStringFromDict:response];
}

- (NSString *)toolSaveSequence:(NSDictionary *)arguments {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";
    if (![bridge isSequenceLoaded]) return @"Error: No sequence is currently open";

    NSString *filename = arguments[@"filename"] ?: @"";

    BOOL success;
    if (filename.length > 0) {
        success = [bridge saveSequence:filename];
    } else {
        success = [bridge saveSequence:nil];
    }

    if (!success) return @"Error: Failed to save sequence";

    NSDictionary *response = @{
        @"success": @YES,
        @"message": @"Sequence saved"
    };
    return [self jsonStringFromDict:response];
}

- (NSString *)toolCloseSequence:(NSDictionary *)arguments {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";

    if (![bridge isSequenceLoaded]) {
        NSDictionary *response = @{
            @"success": @YES,
            @"message": @"No sequence was open"
        };
        return [self jsonStringFromDict:response];
    }

    NSDictionary *info = [bridge getSequenceInfo];
    NSString *sequenceName = info[@"name"] ?: @"";

    BOOL success = [bridge closeSequence];
    if (!success) return @"Error: Failed to close sequence";

    NSDictionary *response = @{
        @"success": @YES,
        @"closedSequence": sequenceName,
        @"message": @"Sequence closed"
    };
    return [self jsonStringFromDict:response];
}

#pragma mark - Tool Implementations: Search and Batch

- (NSString *)toolSearchEffects:(NSDictionary *)arguments {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";
    if (![bridge isSequenceLoaded]) return @"Error: No sequence is currently open";

    NSString *effectNameFilter = arguments[@"effectName"] ?: @"";
    NSString *settingsFilter = arguments[@"settingsFilter"] ?: @"";
    NSInteger filterStart = arguments[@"startTimeMs"] ? [arguments[@"startTimeMs"] integerValue] : -1;
    NSInteger filterEnd = arguments[@"endTimeMs"] ? [arguments[@"endTimeMs"] integerValue] : -1;

    NSMutableArray *matchingEffects = [NSMutableArray array];
    NSArray<NSString *> *allModelNames = [bridge getModelNames];

    for (NSString *modelName in allModelNames) {
        NSArray<NSDictionary *> *effects = [bridge getEffectsForModel:modelName];
        for (NSDictionary *effect in effects) {
            NSString *effectName = effect[@"effectType"] ?: @"";

            // Check effect name filter (case-insensitive partial match)
            if (effectNameFilter.length > 0) {
                if ([effectName rangeOfString:effectNameFilter options:NSCaseInsensitiveSearch].location == NSNotFound) {
                    continue;
                }
            }

            // Check settings filter
            if (settingsFilter.length > 0) {
                NSString *effectSettings = effect[@"settings"] ?: @"";
                if (![self settings:effectSettings matchesFilter:settingsFilter]) {
                    continue;
                }
            }

            // Check time range filter
            if (filterStart >= 0 && filterEnd >= 0) {
                NSInteger effectStart = [effect[@"startTimeMS"] integerValue];
                NSInteger effectEnd = [effect[@"endTimeMS"] integerValue];
                if (effectEnd <= filterStart || effectStart >= filterEnd) {
                    continue;
                }
            }

            [matchingEffects addObject:@{
                @"modelName": modelName,
                @"id": effect[@"id"] ?: @(-1),
                @"name": effectName,
                @"startTimeMs": effect[@"startTimeMS"] ?: @0,
                @"endTimeMs": effect[@"endTimeMS"] ?: @0,
                @"layer": effect[@"layerIndex"] ?: @0,
                @"settings": effect[@"settings"] ?: @"",
                @"palette": effect[@"palette"] ?: @""
            }];
        }
    }

    NSMutableDictionary *response = [@{
        @"success": @YES,
        @"matchCount": @(matchingEffects.count),
        @"effects": matchingEffects
    } mutableCopy];

    if (effectNameFilter.length > 0) response[@"filterEffectName"] = effectNameFilter;
    if (settingsFilter.length > 0) response[@"filterSettings"] = settingsFilter;
    if (filterStart >= 0) response[@"filterStartTimeMs"] = @(filterStart);
    if (filterEnd >= 0) response[@"filterEndTimeMs"] = @(filterEnd);

    return [self jsonStringFromDict:response];
}

- (NSString *)toolBatchUpdateEffects:(NSDictionary *)arguments {
    XLEngineBridge *bridge = self.engineBridge;
    if (!bridge) return @"Error: Engine not available";
    if (![bridge isSequenceLoaded]) return @"Error: No sequence is currently open";

    NSString *effectNameFilter = arguments[@"effectName"] ?: @"";
    NSString *settingsFilter = arguments[@"settingsFilter"] ?: @"";
    NSString *newSettings = arguments[@"newSettings"] ?: @"";
    NSString *newPalette = arguments[@"newPalette"] ?: @"";

    if (newSettings.length == 0 && newPalette.length == 0) {
        return @"Error: Either newSettings or newPalette must be specified";
    }

    // Find matching effects
    NSMutableArray<NSDictionary *> *matchingEffects = [NSMutableArray array];
    NSArray<NSString *> *allModelNames = [bridge getModelNames];

    for (NSString *modelName in allModelNames) {
        NSArray<NSDictionary *> *effects = [bridge getEffectsForModel:modelName];
        for (NSDictionary *effect in effects) {
            NSString *effectName = effect[@"effectType"] ?: @"";

            if (effectNameFilter.length > 0) {
                if ([effectName rangeOfString:effectNameFilter options:NSCaseInsensitiveSearch].location == NSNotFound) {
                    continue;
                }
            }

            if (settingsFilter.length > 0) {
                NSString *effectSettings = effect[@"settings"] ?: @"";
                if (![self settings:effectSettings matchesFilter:settingsFilter]) {
                    continue;
                }
            }

            [matchingEffects addObject:@{
                @"modelName": modelName,
                @"id": effect[@"id"] ?: @(-1),
                @"name": effectName,
                @"layer": effect[@"layerIndex"] ?: @0,
                @"startTimeMs": effect[@"startTimeMS"] ?: @0,
                @"endTimeMs": effect[@"endTimeMS"] ?: @0,
                @"settings": effect[@"settings"] ?: @""
            }];
        }
    }

    if (matchingEffects.count == 0) {
        NSDictionary *response = @{
            @"success": @YES,
            @"updatedCount": @0,
            @"message": @"No effects matched the filter criteria"
        };
        return [self jsonStringFromDict:response];
    }

    // Update matching effects
    NSMutableArray *updatedEffects = [NSMutableArray array];
    NSInteger updateCount = 0;

    for (NSDictionary *match in matchingEffects) {
        NSInteger effectId = [match[@"id"] integerValue];

        if (newSettings.length > 0) {
            // Merge new settings with existing
            NSString *existingSettings = match[@"settings"] ?: @"";
            NSString *mergedSettings = [self mergeSettings:existingSettings withNew:newSettings];
            [bridge setEffectSettings:effectId settings:mergedSettings];
        }

        if (newPalette.length > 0) {
            [bridge setEffectPalette:effectId palette:newPalette];
        }

        updateCount++;
        [updatedEffects addObject:@{
            @"modelName": match[@"modelName"],
            @"id": @(effectId),
            @"name": match[@"name"],
            @"layer": match[@"layer"],
            @"startTimeMs": match[@"startTimeMs"],
            @"endTimeMs": match[@"endTimeMs"]
        }];
    }

    NSMutableDictionary *response = [@{
        @"success": @YES,
        @"updatedCount": @(updateCount),
        @"updatedEffects": updatedEffects
    } mutableCopy];

    if (effectNameFilter.length > 0) response[@"filterEffectName"] = effectNameFilter;
    if (settingsFilter.length > 0) response[@"filterSettings"] = settingsFilter;
    if (newSettings.length > 0) response[@"appliedSettings"] = newSettings;
    if (newPalette.length > 0) response[@"appliedPalette"] = newPalette;

    return [self jsonStringFromDict:response];
}

#pragma mark - Helper: Timing Mark Collection

- (NSArray *)collectTimingMarks:(NSString *)timingTrackName
                        pattern:(NSString *)pattern
                 filterStartMs:(NSInteger)filterStartMs
                   filterEndMs:(NSInteger)filterEndMs {
    XLEngineBridge *bridge = self.engineBridge;

    NSArray<NSDictionary *> *tracks = [bridge getTimingTracks];
    NSDictionary *targetTrack = nil;
    for (NSDictionary *track in tracks) {
        if ([track[@"name"] isEqualToString:timingTrackName]) {
            targetTrack = track;
            break;
        }
    }

    if (!targetTrack) return nil;

    NSInteger layerCount = [targetTrack[@"layerCount"] integerValue];
    NSMutableArray *result = [NSMutableArray array];
    NSInteger markIndex = 0;

    for (NSInteger layer = 0; layer < layerCount; layer++) {
        NSArray<NSDictionary *> *marks = [bridge getTimingMarks:timingTrackName layer:layer];
        for (NSDictionary *mark in marks) {
            NSInteger markStart = [mark[@"startTimeMS"] integerValue];
            NSInteger markEnd = [mark[@"endTimeMS"] integerValue];
            NSString *label = mark[@"label"] ?: @"";

            BOOL includeThisMark = NO;

            if ([pattern isEqualToString:@"all"]) {
                includeThisMark = YES;
            } else if ([pattern isEqualToString:@"even"]) {
                includeThisMark = (markIndex % 2 == 0);
            } else if ([pattern isEqualToString:@"odd"]) {
                includeThisMark = (markIndex % 2 == 1);
            } else {
                includeThisMark = [label isEqualToString:pattern];
            }

            if (includeThisMark && filterStartMs >= 0 && markStart < filterStartMs) {
                includeThisMark = NO;
            }
            if (includeThisMark && filterEndMs >= 0 && markStart >= filterEndMs) {
                includeThisMark = NO;
            }

            if (includeThisMark) {
                [result addObject:@{
                    @"startTimeMs": @(markStart),
                    @"endTimeMs": @(markEnd)
                }];
            }
            markIndex++;
        }
    }

    return result;
}

#pragma mark - Helper: Settings Filter Matching

- (BOOL)settings:(NSString *)effectSettings matchesFilter:(NSString *)filter {
    NSArray *filterPairs = [filter componentsSeparatedByString:@","];
    for (NSString *pair in filterPairs) {
        NSString *trimmed = [pair stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0 && [effectSettings rangeOfString:trimmed].location == NSNotFound) {
            return NO;
        }
    }
    return YES;
}

#pragma mark - Helper: Settings Merge

- (NSString *)mergeSettings:(NSString *)existingSettings withNew:(NSString *)newSettings {
    NSMutableDictionary *settingsDict = [NSMutableDictionary dictionary];

    // Parse existing settings
    NSArray *existingPairs = [existingSettings componentsSeparatedByString:@","];
    for (NSString *pair in existingPairs) {
        NSString *trimmed = [pair stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSRange eqRange = [trimmed rangeOfString:@"="];
        if (eqRange.location != NSNotFound) {
            NSString *key = [trimmed substringToIndex:eqRange.location];
            NSString *value = [trimmed substringFromIndex:eqRange.location + 1];
            settingsDict[key] = value;
        }
    }

    // Merge new settings (overrides existing)
    NSArray *newPairs = [newSettings componentsSeparatedByString:@","];
    for (NSString *pair in newPairs) {
        NSString *trimmed = [pair stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSRange eqRange = [trimmed rangeOfString:@"="];
        if (eqRange.location != NSNotFound) {
            NSString *key = [trimmed substringToIndex:eqRange.location];
            NSString *value = [trimmed substringFromIndex:eqRange.location + 1];
            settingsDict[key] = value;
        }
    }

    // Rebuild settings string
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *key in settingsDict) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, settingsDict[key]]];
    }

    return [pairs componentsJoinedByString:@","];
}

#pragma mark - JSON Helpers

- (NSString *)makeResponseWithId:(NSString *)requestId result:(NSDictionary *)result {
    NSDictionary *response = @{
        @"jsonrpc": @"2.0",
        @"id": requestId ?: @"null",
        @"result": result ?: @{}
    };
    return [self jsonStringFromDict:response];
}

- (NSString *)makeErrorWithId:(NSString *)requestId code:(NSInteger)code message:(NSString *)message {
    NSDictionary *response = @{
        @"jsonrpc": @"2.0",
        @"id": requestId ?: @"null",
        @"error": @{
            @"code": @(code),
            @"message": message ?: @"Unknown error"
        }
    };
    return [self jsonStringFromDict:response];
}

- (NSString *)jsonStringFromDict:(NSDictionary *)dict {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict
                                                      options:NSJSONWritingPrettyPrinted
                                                        error:&error];
    if (error || !jsonData) {
        return @"{}";
    }
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

@end

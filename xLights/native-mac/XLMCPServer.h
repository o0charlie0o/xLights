/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import <Foundation/Foundation.h>

@class XLEngineBridge;
@class XLEffectPresetsWindowController;

/// JSON-RPC 2.0 MCP (Model Context Protocol) server for AI-assisted sequencing.
///
/// Listens on localhost:1225 and provides 22 tools for programmatic control
/// of xLights sequences. Compatible with Claude Code and other MCP clients.
///
/// Uses Apple Network.framework (NWListener) for TCP transport.
/// All tool operations are routed through XLEngineBridge.
///
/// Protocol: newline-delimited JSON-RPC 2.0 messages.
@interface XLMCPServer : NSObject

/// The engine bridge used for all sequence operations.
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Optional preset controller for preset-related tools.
@property (nonatomic, weak) XLEffectPresetsWindowController *presetsController;

/// Initialize with an engine bridge.
- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge;

/// Start the MCP server on the specified port.
/// @param port TCP port to listen on (default: 1225)
/// @return YES if the server started successfully
- (BOOL)startOnPort:(uint16_t)port;

/// Start the MCP server on the default port (1225).
- (BOOL)start;

/// Stop the MCP server and disconnect all clients.
- (void)stop;

/// Check if the server is currently running.
@property (nonatomic, readonly) BOOL isRunning;

/// Get the port the server is listening on.
@property (nonatomic, readonly) uint16_t port;

/// Get the number of connected clients.
@property (nonatomic, readonly) NSUInteger clientCount;

@end

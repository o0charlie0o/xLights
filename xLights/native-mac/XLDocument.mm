#import "XLDocument.h"
#import "XLMainWindowController.h"
#import "XLEngineBridge.h"
#import "../engine/SequenceEngine.h"
#import <string>

@interface XLDocument ()

@property (nonatomic, assign) xlEngine::SequenceEngine *sequenceEngine;
@property (nonatomic, strong) NSWindowController *mainWindowController;
@property (nonatomic, assign) BOOL loadingSequence;

@end

@implementation XLDocument

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        // SequenceEngine will be created when we have an xLightsFrame
        // For now, this is a placeholder. In full integration, we'll
        // get the frame from the app delegate.
        _sequenceEngine = nullptr;
        _loadingSequence = NO;
    }
    return self;
}

- (void)dealloc {
    // Note: We don't own the SequenceEngine - it's owned by xLightsFrame
    _sequenceEngine = nullptr;
}

#pragma mark - Document Type

- (BOOL)isShowFolder {
    if (!self.fileURL) return NO;

    // Check if this is a directory
    NSNumber *isDirectory = nil;
    [self.fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];

    // A show folder is a directory containing xlights_rgbeffects.xml
    if (isDirectory && [isDirectory boolValue]) {
        NSURL *rgbEffectsURL = [self.fileURL URLByAppendingPathComponent:@"xlights_rgbeffects.xml"];
        return [[NSFileManager defaultManager] fileExistsAtPath:rgbEffectsURL.path];
    }

    return NO;
}

- (void *)sequenceEnginePtr {
    return _sequenceEngine;
}

#pragma mark - NSDocument Overrides - Reading

+ (BOOL)autosavesInPlace {
    return YES;
}

- (void)makeWindowControllers {
    // Use the existing XLMainWindowController from Phase 1A
    // This integrates XLDocument with the three-region split view layout
    XLMainWindowController *windowController = [[XLMainWindowController alloc] init];
    [self addWindowController:windowController];
    self.mainWindowController = windowController;

    // Wire up the engine bridge if available
    if (_sequenceEngine && windowController.engineBridge) {
        // The engine bridge will handle communication between
        // the UI and the C++ engine APIs
    }
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError {
    if (_loadingSequence) {
        // Prevent recursive loading
        return YES;
    }

    _loadingSequence = YES;

    BOOL success = NO;

    @try {
        if ([typeName isEqualToString:@"Show Folder"]) {
            success = [self readShowFolder:url error:outError];
        } else if ([typeName isEqualToString:@"xLights Sequence"]) {
            success = [self readXLightsSequence:url error:outError];
        } else if ([typeName isEqualToString:@"FSEQ Sequence"]) {
            success = [self readFSEQSequence:url error:outError];
        } else {
            if (outError) {
                *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                                code:NSFileReadUnknownError
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown document type: %@", typeName]}];
            }
            success = NO;
        }
    }
    @finally {
        _loadingSequence = NO;
    }

    return success;
}

- (BOOL)readShowFolder:(NSURL *)url error:(NSError **)outError {
    // A show folder contains:
    // - xlights_rgbeffects.xml (models, controller configuration)
    // - *.xsq or *.xml files (sequences)
    // - *.fseq files (binary sequences)

    self.showFolderURL = url;

    // Check for required xlights_rgbeffects.xml
    NSURL *rgbEffectsURL = [url URLByAppendingPathComponent:@"xlights_rgbeffects.xml"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:rgbEffectsURL.path]) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                            code:NSFileReadCorruptFileError
                                        userInfo:@{NSLocalizedDescriptionKey: @"Not a valid xLights show folder (missing xlights_rgbeffects.xml)"}];
        }
        return NO;
    }

    // In full integration, we would:
    // 1. Load xlights_rgbeffects.xml (models + controllers)
    // 2. Scan for sequence files
    // 3. Display them in a sequence browser

    // For now, just mark as successfully loaded
    return YES;
}

- (BOOL)readXLightsSequence:(NSURL *)url error:(NSError **)outError {
    if (!_sequenceEngine) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                            code:NSFileReadUnknownError
                                        userInfo:@{NSLocalizedDescriptionKey: @"Sequence engine not initialized"}];
        }
        return NO;
    }

    std::string path = url.path.UTF8String;
    BOOL success = _sequenceEngine->loadSequence(path);

    if (!success && outError) {
        *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                        code:NSFileReadCorruptFileError
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to load sequence file"}];
    }

    // Extract show folder from sequence path if not already set
    if (success && !self.showFolderURL) {
        self.showFolderURL = url.URLByDeletingLastPathComponent;
    }

    return success;
}

- (BOOL)readFSEQSequence:(NSURL *)url error:(NSError **)outError {
    if (!_sequenceEngine) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                            code:NSFileReadUnknownError
                                        userInfo:@{NSLocalizedDescriptionKey: @"Sequence engine not initialized"}];
        }
        return NO;
    }

    std::string path = url.path.UTF8String;
    BOOL success = _sequenceEngine->loadSequence(path);

    if (!success && outError) {
        *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                        code:NSFileReadCorruptFileError
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to load FSEQ file"}];
    }

    // Extract show folder from sequence path if not already set
    if (success && !self.showFolderURL) {
        self.showFolderURL = url.URLByDeletingLastPathComponent;
    }

    return success;
}

#pragma mark - NSDocument Overrides - Writing

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError {
    // Only sequences can be written, not show folders
    if ([typeName isEqualToString:@"Show Folder"]) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                            code:NSFileWriteUnknownError
                                        userInfo:@{NSLocalizedDescriptionKey: @"Cannot save show folder directly"}];
        }
        return NO;
    }

    // Save through the engine bridge so metadata (including audio stems) is included
    XLEngineBridge *bridge = nil;
    for (NSWindowController *wc in self.windowControllers) {
        if ([wc isKindOfClass:[XLMainWindowController class]]) {
            bridge = ((XLMainWindowController *)wc).engineBridge;
            break;
        }
    }

    if (bridge) {
        BOOL success = [bridge saveSequence:url.path];
        if (!success && outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                            code:NSFileWriteUnknownError
                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to save sequence file"}];
        }
        return success;
    }

    // Fallback: direct engine save (no metadata like stems)
    if (!_sequenceEngine) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                            code:NSFileWriteUnknownError
                                        userInfo:@{NSLocalizedDescriptionKey: @"Sequence engine not initialized"}];
        }
        return NO;
    }

    std::string path = url.path.UTF8String;
    BOOL success = _sequenceEngine->saveSequence(path);

    if (!success && outError) {
        *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                        code:NSFileWriteUnknownError
                                    userInfo:@{NSLocalizedDescriptionKey: @"Failed to save sequence file"}];
    }

    return success;
}

#pragma mark - NSDocument Overrides - Closing

- (void)close {
    if (_sequenceEngine) {
        _sequenceEngine->closeSequence();
    }

    [super close];
}

#pragma mark - Public API

- (void)setSequenceEngine:(xlEngine::SequenceEngine *)engine {
    _sequenceEngine = engine;

    // If we already have a file loaded, trigger a reload
    if (self.fileURL && !_loadingSequence) {
        NSError *error = nil;
        [self readFromURL:self.fileURL ofType:self.fileType error:&error];
        if (error) {
            [self presentError:error];
        }
    }
}

@end

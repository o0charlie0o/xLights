#import <Cocoa/Cocoa.h>

@class SequenceEngine;

/// NSDocument subclass for managing .xlights sequence files.
///
/// Supports:
/// - .xlights files (sequence files)
/// - .fseq files (binary sequence files)
/// - Show folder (directory-based document)
///
/// Integrates with:
/// - Recent Files menu (automatic via NSDocument)
/// - Dirty state tracking (unsaved changes dot)
/// - Auto-save and versions
/// - File → Open for both sequences and show folders
/// - Drag-and-drop onto dock icon and app window
@interface XLDocument : NSDocument

/// Path to the currently open show folder.
/// May be different from fileURL for individual sequence files.
@property (nonatomic, copy, nullable) NSURL *showFolderURL;

/// Whether this document represents a show folder vs. individual sequence.
@property (nonatomic, readonly) BOOL isShowFolder;

/// Access to the sequence engine (C++ bridge).
/// May be nil if no sequence is loaded.
@property (nonatomic, readonly, nullable) void *sequenceEnginePtr;

@end

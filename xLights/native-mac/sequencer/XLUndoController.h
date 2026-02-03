#pragma once

/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import <Cocoa/Cocoa.h>

@class XLEffectsGridView;

/// Undo action type enumeration, mirroring the C++ UndoManager pattern.
/// These match UNDO_ACTIONS from xLights/sequencer/UndoManager.h
typedef NS_ENUM(NSInteger, XLUndoActionType) {
    XLUndoActionTypeMarker,          // Group boundary marker
    XLUndoActionTypeEffectAdded,     // Effect was added (undo = delete)
    XLUndoActionTypeEffectDeleted,   // Effect was deleted (undo = re-add)
    XLUndoActionTypeEffectModified,  // Effect settings changed
    XLUndoActionTypeEffectMoved,     // Effect position changed
    XLUndoActionTypeEffectResized,   // Effect duration changed
    XLUndoActionTypeLayerAdded,      // Layer was added
    XLUndoActionTypeLayerDeleted,    // Layer was deleted
    XLUndoActionTypeModelReordered,  // Model row order changed
};

/// Effect state snapshot for undo/redo operations.
/// Uses plain C types to be immune to wxWidgets heap corruption.
typedef struct {
    NSInteger effectID;           // Unique effect identifier
    NSInteger row;                // Row index in the grid
    NSInteger layer;              // Layer within the row
    CGFloat startTimeMS;          // Start time in milliseconds
    CGFloat endTimeMS;            // End time in milliseconds
    NSInteger effectTypeIndex;    // Index into effect type list
    uint32_t colorARGB;           // Primary color (ARGB packed)
    BOOL selected;
    BOOL locked;
    BOOL renderDisabled;
} XLEffectSnapshot;

/// Manages undo/redo operations for the sequencer effects grid.
///
/// This class wraps NSUndoManager and provides a high-level API for
/// registering undoable operations on effects, layers, and models.
/// It mirrors the pattern from xLights/sequencer/UndoManager.h/cpp
/// but uses native Cocoa undo infrastructure.
///
/// Key design decisions:
/// - Uses NSUndoManager for standard macOS Cmd+Z / Cmd+Shift+Z behavior
/// - Supports grouped operations (e.g., moving 5 selected effects = one undo step)
/// - Provides descriptive action names for the Edit menu
/// - State snapshots use plain C structs to avoid heap corruption from wxWidgets
///
/// Integration with XLEffectsGridView:
/// - Grid view holds a reference to this controller
/// - Before any mutating operation, call the appropriate capture method
/// - After the operation completes, call commitUndoGroup if using grouped undo
@interface XLUndoController : NSObject

/// The underlying NSUndoManager. This can be connected to a window
/// or document for automatic menu item management.
@property (nonatomic, strong, readonly) NSUndoManager *undoManager;

/// The effects grid view this controller manages undo for.
/// Set via initWithGridView: or setGridView:
@property (nonatomic, weak) XLEffectsGridView *gridView;

/// Initialize with a grid view to manage.
- (instancetype)initWithGridView:(XLEffectsGridView *)gridView;

#pragma mark - Undo Group Management

/// Begin a grouped undo operation. Call this before a batch of related changes
/// (e.g., moving multiple selected effects). All changes until endUndoGrouping
/// will be treated as a single undoable action.
- (void)beginUndoGrouping;

/// Begin a grouped undo operation with a descriptive name that appears in the
/// Edit menu (e.g., "Move Effects", "Delete Effects").
- (void)beginUndoGroupingWithActionName:(NSString *)actionName;

/// End the current grouped undo operation. If no changes were registered,
/// the group is discarded.
- (void)endUndoGrouping;

/// Discard the current undo group without committing it.
/// Use this when an operation is cancelled.
- (void)cancelUndoGrouping;

#pragma mark - Effect Operations

/// Capture an effect before it is modified. Call this BEFORE changing
/// effect settings, color, or other properties.
/// @param snapshot The current state of the effect
/// @param actionName Descriptive name (e.g., "Modify Effect")
- (void)captureEffectToBeModified:(XLEffectSnapshot)snapshot
                       actionName:(NSString *)actionName;

/// Capture an effect before it is moved. Call this BEFORE changing
/// the effect's start/end time or row position.
/// @param snapshot The current state (position) of the effect
/// @param actionName Descriptive name (e.g., "Move Effect")
- (void)captureEffectToBeMoved:(XLEffectSnapshot)snapshot
                    actionName:(NSString *)actionName;

/// Capture an effect before it is resized. Call this BEFORE changing
/// the effect's start/end time.
/// @param snapshot The current state (timing) of the effect
/// @param actionName Descriptive name (e.g., "Resize Effect")
- (void)captureEffectToBeResized:(XLEffectSnapshot)snapshot
                      actionName:(NSString *)actionName;

/// Capture an effect that is being deleted. Call this BEFORE removing
/// the effect from the data source.
/// @param snapshot The complete state of the effect to restore on undo
/// @param actionName Descriptive name (e.g., "Delete Effect")
- (void)captureEffectToBeDeleted:(XLEffectSnapshot)snapshot
                      actionName:(NSString *)actionName;

/// Register that an effect was just added. Call this AFTER adding a new effect.
/// On undo, the effect will be removed.
/// @param effectID The ID of the newly added effect
/// @param actionName Descriptive name (e.g., "Add Effect")
- (void)registerEffectAdded:(NSInteger)effectID
                 actionName:(NSString *)actionName;

#pragma mark - Batch Operations

/// Capture multiple effects before they are moved as a group.
/// @param snapshots Array of XLEffectSnapshot wrapped in NSValue
/// @param actionName Descriptive name (e.g., "Move 5 Effects")
- (void)captureEffectsToBeMoved:(NSArray<NSValue *> *)snapshots
                     actionName:(NSString *)actionName;

/// Capture multiple effects before they are deleted.
/// @param snapshots Array of XLEffectSnapshot wrapped in NSValue
/// @param actionName Descriptive name (e.g., "Delete 5 Effects")
- (void)captureEffectsToBeDeleted:(NSArray<NSValue *> *)snapshots
                       actionName:(NSString *)actionName;

#pragma mark - Layer Operations

/// Capture a layer before it is deleted.
/// @param rowIndex The row index of the layer
/// @param layerIndex The layer index within the row
/// @param actionName Descriptive name
- (void)captureLayerToBeDeleted:(NSInteger)rowIndex
                     layerIndex:(NSInteger)layerIndex
                     actionName:(NSString *)actionName;

/// Register that a layer was just added.
/// @param rowIndex The row index of the layer
/// @param layerIndex The layer index within the row
/// @param actionName Descriptive name
- (void)registerLayerAdded:(NSInteger)rowIndex
                layerIndex:(NSInteger)layerIndex
                actionName:(NSString *)actionName;

#pragma mark - Model/Row Operations

/// Capture a model reorder operation.
/// @param fromRow Original row index
/// @param toRow New row index
/// @param actionName Descriptive name (e.g., "Reorder Model")
- (void)captureModelReorder:(NSInteger)fromRow
                      toRow:(NSInteger)toRow
                 actionName:(NSString *)actionName;

#pragma mark - State Queries

/// Returns YES if there are operations that can be undone.
- (BOOL)canUndo;

/// Returns YES if there are operations that can be redone.
- (BOOL)canRedo;

/// Returns the descriptive name of the next undo operation,
/// suitable for display in the Edit menu (e.g., "Undo Move Effect").
- (NSString *)undoMenuItemTitle;

/// Returns the descriptive name of the next redo operation,
/// suitable for display in the Edit menu (e.g., "Redo Move Effect").
- (NSString *)redoMenuItemTitle;

#pragma mark - Undo/Redo Actions

/// Perform the next undo operation. Usually called by the responder chain
/// in response to Cmd+Z.
- (void)undo;

/// Perform the next redo operation. Usually called by the responder chain
/// in response to Cmd+Shift+Z.
- (void)redo;

/// Clear all undo/redo history. Call when loading a new sequence.
- (void)clearUndoHistory;

@end

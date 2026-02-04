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
#import <simd/simd.h>

@class XLEngineBridge;

NS_ASSUME_NONNULL_BEGIN

/// Undo action type enumeration for Layout operations.
typedef NS_ENUM(NSInteger, XLLayoutUndoActionType) {
    XLLayoutUndoActionTypeModelTranslate,   // Model position changed
    XLLayoutUndoActionTypeModelScale,       // Model scale changed
    XLLayoutUndoActionTypeModelRotate,      // Model rotation changed
    XLLayoutUndoActionTypeModelCreate,      // Model was created
    XLLayoutUndoActionTypeModelDelete,      // Model was deleted
    XLLayoutUndoActionTypeModelDuplicate,   // Model was duplicated
    XLLayoutUndoActionTypeModelProperty,    // Model property changed
};

/// Snapshot of a model's transform state for undo/redo operations.
/// Uses plain C types to be immune to wxWidgets heap corruption.
typedef struct {
    simd_float3 position;       // World position (WorldPosX, Y, Z)
    simd_float3 scale;          // Scale factors (ScaleX, Y, Z)
    simd_float3 rotation;       // Rotation angles in degrees (RotateX, Y, Z)
} XLModelTransformSnapshot;

/// Manages undo/redo operations for Layout model manipulation.
///
/// This class wraps NSUndoManager and provides a high-level API for
/// registering undoable operations on models: translate, scale, rotate,
/// create, delete, and duplicate.
///
/// Integration:
/// - Layout view controller holds a reference to this controller
/// - Before any manipulation begins, call captureModelState
/// - When manipulation ends, call registerManipulation
/// - For create/delete/duplicate, call the appropriate register method
@interface XLLayoutUndoController : NSObject

/// The underlying NSUndoManager. Can be connected to window for menu management.
@property (nonatomic, strong, readonly) NSUndoManager *undoManager;

/// Engine bridge for applying undo/redo changes to model data
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Delegate to notify when undo/redo occurs
@property (nonatomic, weak, nullable) id delegate;

/// Initialize with an engine bridge for model operations.
- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge;

#pragma mark - Model Transform Operations

/// Capture a model's transform state before manipulation begins.
/// Call this at the start of drag operations.
/// @param modelName Name of the model being manipulated
/// @param snapshot The current transform state
- (void)captureModelTransform:(NSString *)modelName
                     snapshot:(XLModelTransformSnapshot)snapshot;

/// Register a completed translate operation.
/// @param modelName Name of the model
/// @param newSnapshot The new transform state after manipulation
- (void)registerTranslate:(NSString *)modelName
              newSnapshot:(XLModelTransformSnapshot)newSnapshot;

/// Register a completed scale operation.
/// @param modelName Name of the model
/// @param newSnapshot The new transform state after manipulation
- (void)registerScale:(NSString *)modelName
          newSnapshot:(XLModelTransformSnapshot)newSnapshot;

/// Register a completed rotate operation.
/// @param modelName Name of the model
/// @param newSnapshot The new transform state after manipulation
- (void)registerRotate:(NSString *)modelName
           newSnapshot:(XLModelTransformSnapshot)newSnapshot;

#pragma mark - Model Create/Delete/Duplicate

/// Register that a model was created.
/// On undo, the model will be deleted.
/// @param modelName Name of the created model
/// @param modelData Serialized model data for re-creation on redo
- (void)registerModelCreated:(NSString *)modelName
                   modelData:(NSDictionary *)modelData;

/// Register that a model is about to be deleted.
/// On undo, the model will be re-created.
/// @param modelName Name of the model being deleted
/// @param modelData Serialized model data for recreation on undo
- (void)registerModelDeleted:(NSString *)modelName
                   modelData:(NSDictionary *)modelData;

/// Register that a model was duplicated.
/// On undo, the duplicate will be deleted.
/// @param originalName Name of the original model
/// @param duplicateName Name of the new duplicate
/// @param duplicateData Serialized data of the duplicate
- (void)registerModelDuplicated:(NSString *)originalName
                  duplicateName:(NSString *)duplicateName
                  duplicateData:(NSDictionary *)duplicateData;

#pragma mark - Model Property Operations

/// Register a property change.
/// @param modelName Name of the model
/// @param key Property key
/// @param oldValue Previous value
/// @param newValue New value
- (void)registerPropertyChange:(NSString *)modelName
                           key:(NSString *)key
                      oldValue:(nullable id)oldValue
                      newValue:(nullable id)newValue;

#pragma mark - State Queries

/// Returns YES if there are operations that can be undone.
- (BOOL)canUndo;

/// Returns YES if there are operations that can be redone.
- (BOOL)canRedo;

/// Returns the descriptive name of the next undo operation.
- (NSString *)undoMenuItemTitle;

/// Returns the descriptive name of the next redo operation.
- (NSString *)redoMenuItemTitle;

#pragma mark - Undo/Redo Actions

/// Perform the next undo operation.
- (void)undo;

/// Perform the next redo operation.
- (void)redo;

/// Clear all undo/redo history. Call when loading a new layout.
- (void)clearUndoHistory;

@end

/// Protocol for objects that want to be notified of undo/redo events.
@protocol XLLayoutUndoDelegate <NSObject>
@optional

/// Called after an undo/redo operation completes.
/// Use this to refresh the UI.
- (void)layoutUndoController:(XLLayoutUndoController *)controller
        didRestoreModelNamed:(NSString *)modelName;

/// Called after an undo/redo of model creation/deletion.
- (void)layoutUndoController:(XLLayoutUndoController *)controller
         didChangeModelNamed:(NSString *)modelName
                   wasCreate:(BOOL)wasCreate;

@end

NS_ASSUME_NONNULL_END

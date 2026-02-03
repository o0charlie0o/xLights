/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLUndoController.h"
#import "XLEffectsGridView.h"

@interface XLUndoController ()

@property (nonatomic, strong, readwrite) NSUndoManager *undoManager;
@property (nonatomic, assign) NSInteger undoGroupLevel;

@end

@implementation XLUndoController

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _undoManager = [[NSUndoManager alloc] init];
        _undoGroupLevel = 0;
    }
    return self;
}

- (instancetype)initWithGridView:(XLEffectsGridView *)gridView {
    self = [self init];
    if (self) {
        _gridView = gridView;
    }
    return self;
}

#pragma mark - Undo Group Management

- (void)beginUndoGrouping {
    [_undoManager beginUndoGrouping];
    _undoGroupLevel++;
}

- (void)beginUndoGroupingWithActionName:(NSString *)actionName {
    [self beginUndoGrouping];
    [_undoManager setActionName:actionName];
}

- (void)endUndoGrouping {
    if (_undoGroupLevel > 0) {
        [_undoManager endUndoGrouping];
        _undoGroupLevel--;
    }
}

- (void)cancelUndoGrouping {
    if (_undoGroupLevel > 0) {
        [_undoManager endUndoGrouping];
        _undoGroupLevel--;
        if ([_undoManager canUndo]) {
            // Remove the just-ended group
            [_undoManager undo];
            // Clear the redo that was created
            [_undoManager removeAllActionsWithTarget:self];
        }
    }
}

#pragma mark - Effect Operations

- (void)captureEffectToBeModified:(XLEffectSnapshot)snapshot
                       actionName:(NSString *)actionName {
    // Store the snapshot as NSValue (safe because XLEffectSnapshot is plain C)
    NSValue *snapshotValue = [NSValue valueWithBytes:&snapshot objCType:@encode(XLEffectSnapshot)];

    [[_undoManager prepareWithInvocationTarget:self]
        restoreModifiedEffect:snapshotValue];

    if (actionName && _undoGroupLevel == 0) {
        [_undoManager setActionName:actionName];
    }
}

- (void)restoreModifiedEffect:(NSValue *)snapshotValue {
    XLEffectSnapshot snapshot;
    [snapshotValue getValue:&snapshot];

    // Capture current state for redo before restoring
    XLEffectSnapshot currentSnapshot = [self currentSnapshotForEffectID:snapshot.effectID];
    NSValue *currentValue = [NSValue valueWithBytes:&currentSnapshot objCType:@encode(XLEffectSnapshot)];

    [[_undoManager prepareWithInvocationTarget:self]
        restoreModifiedEffect:currentValue];

    // Notify delegate to apply the restored state
    [self applyEffectSnapshot:snapshot actionType:XLUndoActionTypeEffectModified];
}

- (void)captureEffectToBeMoved:(XLEffectSnapshot)snapshot
                    actionName:(NSString *)actionName {
    NSValue *snapshotValue = [NSValue valueWithBytes:&snapshot objCType:@encode(XLEffectSnapshot)];

    [[_undoManager prepareWithInvocationTarget:self]
        restoreMovedEffect:snapshotValue];

    if (actionName && _undoGroupLevel == 0) {
        [_undoManager setActionName:actionName];
    }
}

- (void)restoreMovedEffect:(NSValue *)snapshotValue {
    XLEffectSnapshot snapshot;
    [snapshotValue getValue:&snapshot];

    // Capture current position for redo
    XLEffectSnapshot currentSnapshot = [self currentSnapshotForEffectID:snapshot.effectID];
    NSValue *currentValue = [NSValue valueWithBytes:&currentSnapshot objCType:@encode(XLEffectSnapshot)];

    [[_undoManager prepareWithInvocationTarget:self]
        restoreMovedEffect:currentValue];

    [self applyEffectSnapshot:snapshot actionType:XLUndoActionTypeEffectMoved];
}

- (void)captureEffectToBeResized:(XLEffectSnapshot)snapshot
                      actionName:(NSString *)actionName {
    NSValue *snapshotValue = [NSValue valueWithBytes:&snapshot objCType:@encode(XLEffectSnapshot)];

    [[_undoManager prepareWithInvocationTarget:self]
        restoreResizedEffect:snapshotValue];

    if (actionName && _undoGroupLevel == 0) {
        [_undoManager setActionName:actionName];
    }
}

- (void)restoreResizedEffect:(NSValue *)snapshotValue {
    XLEffectSnapshot snapshot;
    [snapshotValue getValue:&snapshot];

    // Capture current size for redo
    XLEffectSnapshot currentSnapshot = [self currentSnapshotForEffectID:snapshot.effectID];
    NSValue *currentValue = [NSValue valueWithBytes:&currentSnapshot objCType:@encode(XLEffectSnapshot)];

    [[_undoManager prepareWithInvocationTarget:self]
        restoreResizedEffect:currentValue];

    [self applyEffectSnapshot:snapshot actionType:XLUndoActionTypeEffectResized];
}

- (void)captureEffectToBeDeleted:(XLEffectSnapshot)snapshot
                      actionName:(NSString *)actionName {
    NSValue *snapshotValue = [NSValue valueWithBytes:&snapshot objCType:@encode(XLEffectSnapshot)];

    [[_undoManager prepareWithInvocationTarget:self]
        restoreDeletedEffect:snapshotValue];

    if (actionName && _undoGroupLevel == 0) {
        [_undoManager setActionName:actionName];
    }
}

- (void)restoreDeletedEffect:(NSValue *)snapshotValue {
    XLEffectSnapshot snapshot;
    [snapshotValue getValue:&snapshot];

    // Re-add the effect - undo of delete is add
    NSInteger newEffectID = [self recreateEffect:snapshot];

    // Register the add for redo (which will delete again)
    [[_undoManager prepareWithInvocationTarget:self]
        undoEffectAdded:newEffectID];
}

- (void)registerEffectAdded:(NSInteger)effectID
                 actionName:(NSString *)actionName {
    [[_undoManager prepareWithInvocationTarget:self]
        undoEffectAdded:effectID];

    if (actionName && _undoGroupLevel == 0) {
        [_undoManager setActionName:actionName];
    }
}

- (void)undoEffectAdded:(NSInteger)effectID {
    // Capture the effect state before deleting it
    XLEffectSnapshot snapshot = [self currentSnapshotForEffectID:effectID];
    NSValue *snapshotValue = [NSValue valueWithBytes:&snapshot objCType:@encode(XLEffectSnapshot)];

    // Register for redo (re-add)
    [[_undoManager prepareWithInvocationTarget:self]
        restoreDeletedEffect:snapshotValue];

    // Delete the effect
    [self deleteEffectWithID:effectID];
}

#pragma mark - Batch Operations

- (void)captureEffectsToBeMoved:(NSArray<NSValue *> *)snapshots
                     actionName:(NSString *)actionName {
    [self beginUndoGroupingWithActionName:actionName];

    for (NSValue *snapshotValue in snapshots) {
        [[_undoManager prepareWithInvocationTarget:self]
            restoreMovedEffect:snapshotValue];
    }

    [self endUndoGrouping];
}

- (void)captureEffectsToBeDeleted:(NSArray<NSValue *> *)snapshots
                       actionName:(NSString *)actionName {
    [self beginUndoGroupingWithActionName:actionName];

    for (NSValue *snapshotValue in snapshots) {
        [[_undoManager prepareWithInvocationTarget:self]
            restoreDeletedEffect:snapshotValue];
    }

    [self endUndoGrouping];
}

#pragma mark - Layer Operations

- (void)captureLayerToBeDeleted:(NSInteger)rowIndex
                     layerIndex:(NSInteger)layerIndex
                     actionName:(NSString *)actionName {
    [[_undoManager prepareWithInvocationTarget:self]
        restoreDeletedLayer:rowIndex layerIndex:layerIndex];

    if (actionName && _undoGroupLevel == 0) {
        [_undoManager setActionName:actionName];
    }
}

- (void)restoreDeletedLayer:(NSInteger)rowIndex layerIndex:(NSInteger)layerIndex {
    // Register redo action
    [[_undoManager prepareWithInvocationTarget:self]
        undoLayerAdded:rowIndex layerIndex:layerIndex];

    // Re-add the layer
    [self recreateLayerAtRow:rowIndex layerIndex:layerIndex];
}

- (void)registerLayerAdded:(NSInteger)rowIndex
                layerIndex:(NSInteger)layerIndex
                actionName:(NSString *)actionName {
    [[_undoManager prepareWithInvocationTarget:self]
        undoLayerAdded:rowIndex layerIndex:layerIndex];

    if (actionName && _undoGroupLevel == 0) {
        [_undoManager setActionName:actionName];
    }
}

- (void)undoLayerAdded:(NSInteger)rowIndex layerIndex:(NSInteger)layerIndex {
    // Register for redo (re-add)
    [[_undoManager prepareWithInvocationTarget:self]
        restoreDeletedLayer:rowIndex layerIndex:layerIndex];

    // Delete the layer
    [self deleteLayerAtRow:rowIndex layerIndex:layerIndex];
}

#pragma mark - Model/Row Operations

- (void)captureModelReorder:(NSInteger)fromRow
                      toRow:(NSInteger)toRow
                 actionName:(NSString *)actionName {
    [[_undoManager prepareWithInvocationTarget:self]
        restoreModelReorder:toRow toRow:fromRow];

    if (actionName && _undoGroupLevel == 0) {
        [_undoManager setActionName:actionName];
    }
}

- (void)restoreModelReorder:(NSInteger)fromRow toRow:(NSInteger)toRow {
    // Register reverse operation for redo
    [[_undoManager prepareWithInvocationTarget:self]
        restoreModelReorder:toRow toRow:fromRow];

    // Apply the reorder
    [self applyModelReorder:fromRow toRow:toRow];
}

#pragma mark - State Queries

- (BOOL)canUndo {
    return [_undoManager canUndo];
}

- (BOOL)canRedo {
    return [_undoManager canRedo];
}

- (NSString *)undoMenuItemTitle {
    if ([_undoManager canUndo]) {
        NSString *actionName = [_undoManager undoActionName];
        if (actionName.length > 0) {
            return [NSString stringWithFormat:@"Undo %@", actionName];
        }
        return @"Undo";
    }
    return @"Undo";
}

- (NSString *)redoMenuItemTitle {
    if ([_undoManager canRedo]) {
        NSString *actionName = [_undoManager redoActionName];
        if (actionName.length > 0) {
            return [NSString stringWithFormat:@"Redo %@", actionName];
        }
        return @"Redo";
    }
    return @"Redo";
}

#pragma mark - Undo/Redo Actions

- (void)undo {
    if ([_undoManager canUndo]) {
        [_undoManager undo];
        [_gridView reloadData];
        [_gridView setNeedsDisplay];
    }
}

- (void)redo {
    if ([_undoManager canRedo]) {
        [_undoManager redo];
        [_gridView reloadData];
        [_gridView setNeedsDisplay];
    }
}

- (void)clearUndoHistory {
    [_undoManager removeAllActions];
}

#pragma mark - Private Helpers (Grid Integration)

- (XLEffectSnapshot)currentSnapshotForEffectID:(NSInteger)effectID {
    XLEffectSnapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    snapshot.effectID = effectID;

    // In a real implementation, this would query the grid view or data source
    // for the current state of the effect with the given ID.
    // For now, we return a placeholder that the grid view delegate can fill in.

    // The grid view integration will need to provide this data
    // through a delegate method or by accessing the render info array directly.

    return snapshot;
}

- (void)applyEffectSnapshot:(XLEffectSnapshot)snapshot actionType:(XLUndoActionType)actionType {
    // Notify the grid view to apply the snapshot.
    // This will be connected to the grid view's data source to actually
    // modify the underlying effect data.

    // Post a notification that the grid view and its data source can observe
    NSDictionary *userInfo = @{
        @"effectID": @(snapshot.effectID),
        @"row": @(snapshot.row),
        @"layer": @(snapshot.layer),
        @"startTimeMS": @(snapshot.startTimeMS),
        @"endTimeMS": @(snapshot.endTimeMS),
        @"effectTypeIndex": @(snapshot.effectTypeIndex),
        @"colorARGB": @(snapshot.colorARGB),
        @"actionType": @(actionType)
    };

    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"XLUndoControllerDidRestoreEffect"
                      object:self
                    userInfo:userInfo];
}

- (NSInteger)recreateEffect:(XLEffectSnapshot)snapshot {
    // Notify the grid view to recreate the deleted effect
    NSDictionary *userInfo = @{
        @"effectID": @(snapshot.effectID),
        @"row": @(snapshot.row),
        @"layer": @(snapshot.layer),
        @"startTimeMS": @(snapshot.startTimeMS),
        @"endTimeMS": @(snapshot.endTimeMS),
        @"effectTypeIndex": @(snapshot.effectTypeIndex),
        @"colorARGB": @(snapshot.colorARGB)
    };

    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"XLUndoControllerDidRecreateEffect"
                      object:self
                    userInfo:userInfo];

    // Return the new effect ID (in real impl, would be provided by the data source)
    return snapshot.effectID;
}

- (void)deleteEffectWithID:(NSInteger)effectID {
    // Notify the grid view to delete the effect
    NSDictionary *userInfo = @{
        @"effectID": @(effectID)
    };

    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"XLUndoControllerDidDeleteEffect"
                      object:self
                    userInfo:userInfo];
}

- (void)recreateLayerAtRow:(NSInteger)rowIndex layerIndex:(NSInteger)layerIndex {
    NSDictionary *userInfo = @{
        @"rowIndex": @(rowIndex),
        @"layerIndex": @(layerIndex)
    };

    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"XLUndoControllerDidRecreateLayer"
                      object:self
                    userInfo:userInfo];
}

- (void)deleteLayerAtRow:(NSInteger)rowIndex layerIndex:(NSInteger)layerIndex {
    NSDictionary *userInfo = @{
        @"rowIndex": @(rowIndex),
        @"layerIndex": @(layerIndex)
    };

    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"XLUndoControllerDidDeleteLayer"
                      object:self
                    userInfo:userInfo];
}

- (void)applyModelReorder:(NSInteger)fromRow toRow:(NSInteger)toRow {
    NSDictionary *userInfo = @{
        @"fromRow": @(fromRow),
        @"toRow": @(toRow)
    };

    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"XLUndoControllerDidReorderModel"
                      object:self
                    userInfo:userInfo];
}

@end

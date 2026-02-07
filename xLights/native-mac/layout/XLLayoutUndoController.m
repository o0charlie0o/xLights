/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLLayoutUndoController.h"
#import "../XLEngineBridge.h"

/// Internal storage for captured state before manipulation
@interface XLLayoutUndoController ()

@property (nonatomic, strong, readwrite) NSUndoManager *undoManager;
@property (nonatomic, strong) NSString *capturedModelName;
@property (nonatomic, assign) XLModelTransformSnapshot capturedSnapshot;
@property (nonatomic, assign) BOOL hasCapture;

@end

@implementation XLLayoutUndoController

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _undoManager = [[NSUndoManager alloc] init];
        _undoManager.levelsOfUndo = 50;
        _hasCapture = NO;
    }
    return self;
}

- (instancetype)initWithEngineBridge:(XLEngineBridge *)engineBridge {
    self = [self init];
    if (self) {
        _engineBridge = engineBridge;
    }
    return self;
}

#pragma mark - Model Transform Operations

- (void)captureModelTransform:(NSString *)modelName
                     snapshot:(XLModelTransformSnapshot)snapshot {
    _capturedModelName = [modelName copy];
    _capturedSnapshot = snapshot;
    _hasCapture = YES;
}

- (void)registerTranslate:(NSString *)modelName
              newSnapshot:(XLModelTransformSnapshot)newSnapshot {
    if (!_hasCapture || ![_capturedModelName isEqualToString:modelName]) {
        return;
    }

    [self registerTransformChange:modelName
                      oldSnapshot:_capturedSnapshot
                      newSnapshot:newSnapshot
                       actionName:@"Move Model"
                       actionType:XLLayoutUndoActionTypeModelTranslate];

    _hasCapture = NO;
}

- (void)registerScale:(NSString *)modelName
          newSnapshot:(XLModelTransformSnapshot)newSnapshot {
    if (!_hasCapture || ![_capturedModelName isEqualToString:modelName]) {
        return;
    }

    [self registerTransformChange:modelName
                      oldSnapshot:_capturedSnapshot
                      newSnapshot:newSnapshot
                       actionName:@"Scale Model"
                       actionType:XLLayoutUndoActionTypeModelScale];

    _hasCapture = NO;
}

- (void)registerRotate:(NSString *)modelName
           newSnapshot:(XLModelTransformSnapshot)newSnapshot {
    if (!_hasCapture || ![_capturedModelName isEqualToString:modelName]) {
        return;
    }

    [self registerTransformChange:modelName
                      oldSnapshot:_capturedSnapshot
                      newSnapshot:newSnapshot
                       actionName:@"Rotate Model"
                       actionType:XLLayoutUndoActionTypeModelRotate];

    _hasCapture = NO;
}

- (void)registerTransformChange:(NSString *)modelName
                    oldSnapshot:(XLModelTransformSnapshot)oldSnapshot
                    newSnapshot:(XLModelTransformSnapshot)newSnapshot
                     actionName:(NSString *)actionName
                     actionType:(XLLayoutUndoActionType)actionType {

    // Check if there was actually a change
    BOOL changed = NO;
    if (actionType == XLLayoutUndoActionTypeModelTranslate) {
        changed = !simd_equal(oldSnapshot.position, newSnapshot.position);
    } else if (actionType == XLLayoutUndoActionTypeModelScale) {
        changed = !simd_equal(oldSnapshot.scale, newSnapshot.scale);
    } else if (actionType == XLLayoutUndoActionTypeModelRotate) {
        changed = !simd_equal(oldSnapshot.rotation, newSnapshot.rotation);
    }

    if (!changed) {
        return;
    }

    // Store snapshots as dictionaries for undo
    NSDictionary *oldState = [self dictionaryFromSnapshot:oldSnapshot modelName:modelName];
    NSDictionary *newState = [self dictionaryFromSnapshot:newSnapshot modelName:modelName];

    [[_undoManager prepareWithInvocationTarget:self]
        restoreTransform:oldState fromState:newState actionType:actionType];

    [_undoManager setActionName:actionName];
}

- (void)restoreTransform:(NSDictionary *)targetState
               fromState:(NSDictionary *)currentState
              actionType:(XLLayoutUndoActionType)actionType {

    NSString *modelName = targetState[@"modelName"];
    if (!modelName || !_engineBridge) {
        return;
    }

    // Register redo
    [[_undoManager prepareWithInvocationTarget:self]
        restoreTransform:currentState fromState:targetState actionType:actionType];

    // Apply the transform
    XLModelTransformSnapshot snapshot = [self snapshotFromDictionary:targetState];
    [self applySnapshotToModel:modelName snapshot:snapshot];

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(layoutUndoController:didRestoreModelNamed:)]) {
        [_delegate layoutUndoController:self didRestoreModelNamed:modelName];
    }
}

- (void)applySnapshotToModel:(NSString *)modelName snapshot:(XLModelTransformSnapshot)snapshot {
    [_engineBridge updateModelProperty:modelName key:@"WorldPosX" value:@(snapshot.position.x)];
    [_engineBridge updateModelProperty:modelName key:@"WorldPosY" value:@(snapshot.position.y)];
    [_engineBridge updateModelProperty:modelName key:@"WorldPosZ" value:@(snapshot.position.z)];
    [_engineBridge updateModelProperty:modelName key:@"ScaleX" value:@(snapshot.scale.x)];
    [_engineBridge updateModelProperty:modelName key:@"ScaleY" value:@(snapshot.scale.y)];
    [_engineBridge updateModelProperty:modelName key:@"ScaleZ" value:@(snapshot.scale.z)];
    [_engineBridge updateModelProperty:modelName key:@"RotateX" value:@(snapshot.rotation.x)];
    [_engineBridge updateModelProperty:modelName key:@"RotateY" value:@(snapshot.rotation.y)];
    [_engineBridge updateModelProperty:modelName key:@"RotateZ" value:@(snapshot.rotation.z)];
}

#pragma mark - Model Create/Delete/Duplicate

- (void)registerModelCreated:(NSString *)modelName
                   modelData:(NSDictionary *)modelData {
    NSDictionary *info = @{
        @"modelName": modelName,
        @"modelData": modelData ?: @{}
    };

    [[_undoManager prepareWithInvocationTarget:self]
        undoModelCreated:info];

    [_undoManager setActionName:@"Create Model"];
}

- (void)undoModelCreated:(NSDictionary *)info {
    NSString *modelName = info[@"modelName"];
    NSDictionary *modelData = info[@"modelData"];

    if (!modelName || !_engineBridge) {
        return;
    }

    // Register redo (re-create)
    [[_undoManager prepareWithInvocationTarget:self]
        redoModelCreated:info];

    // Delete the model
    [_engineBridge deleteModel:modelName];

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(layoutUndoController:didChangeModelNamed:wasCreate:)]) {
        [_delegate layoutUndoController:self didChangeModelNamed:modelName wasCreate:NO];
    }
}

- (void)redoModelCreated:(NSDictionary *)info {
    NSString *modelName = info[@"modelName"];
    NSDictionary *modelData = info[@"modelData"];

    if (!modelName || !_engineBridge) {
        return;
    }

    // Register undo (delete)
    [[_undoManager prepareWithInvocationTarget:self]
        undoModelCreated:info];

    // Re-create the model
    [_engineBridge createModelFromData:modelData withName:modelName];

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(layoutUndoController:didChangeModelNamed:wasCreate:)]) {
        [_delegate layoutUndoController:self didChangeModelNamed:modelName wasCreate:YES];
    }
}

- (void)registerModelDeleted:(NSString *)modelName
                   modelData:(NSDictionary *)modelData {
    NSDictionary *info = @{
        @"modelName": modelName,
        @"modelData": modelData ?: @{}
    };

    [[_undoManager prepareWithInvocationTarget:self]
        undoModelDeleted:info];

    [_undoManager setActionName:@"Delete Model"];
}

- (void)undoModelDeleted:(NSDictionary *)info {
    NSString *modelName = info[@"modelName"];
    NSDictionary *modelData = info[@"modelData"];

    if (!modelName || !_engineBridge) {
        return;
    }

    // Register redo (delete again)
    [[_undoManager prepareWithInvocationTarget:self]
        redoModelDeleted:info];

    // Re-create the model
    [_engineBridge createModelFromData:modelData withName:modelName];

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(layoutUndoController:didChangeModelNamed:wasCreate:)]) {
        [_delegate layoutUndoController:self didChangeModelNamed:modelName wasCreate:YES];
    }
}

- (void)redoModelDeleted:(NSDictionary *)info {
    NSString *modelName = info[@"modelName"];

    if (!modelName || !_engineBridge) {
        return;
    }

    // Register undo (re-create)
    [[_undoManager prepareWithInvocationTarget:self]
        undoModelDeleted:info];

    // Delete the model
    [_engineBridge deleteModel:modelName];

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(layoutUndoController:didChangeModelNamed:wasCreate:)]) {
        [_delegate layoutUndoController:self didChangeModelNamed:modelName wasCreate:NO];
    }
}

- (void)registerModelDuplicated:(NSString *)originalName
                  duplicateName:(NSString *)duplicateName
                  duplicateData:(NSDictionary *)duplicateData {
    NSDictionary *info = @{
        @"originalName": originalName,
        @"duplicateName": duplicateName,
        @"duplicateData": duplicateData ?: @{}
    };

    [[_undoManager prepareWithInvocationTarget:self]
        undoModelDuplicated:info];

    [_undoManager setActionName:@"Duplicate Model"];
}

- (void)undoModelDuplicated:(NSDictionary *)info {
    NSString *duplicateName = info[@"duplicateName"];

    if (!duplicateName || !_engineBridge) {
        return;
    }

    // Register redo
    [[_undoManager prepareWithInvocationTarget:self]
        redoModelDuplicated:info];

    // Delete the duplicate
    [_engineBridge deleteModel:duplicateName];

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(layoutUndoController:didChangeModelNamed:wasCreate:)]) {
        [_delegate layoutUndoController:self didChangeModelNamed:duplicateName wasCreate:NO];
    }
}

- (void)redoModelDuplicated:(NSDictionary *)info {
    NSString *duplicateName = info[@"duplicateName"];
    NSDictionary *duplicateData = info[@"duplicateData"];

    if (!duplicateName || !_engineBridge) {
        return;
    }

    // Register undo
    [[_undoManager prepareWithInvocationTarget:self]
        undoModelDuplicated:info];

    // Re-create the duplicate
    [_engineBridge createModelFromData:duplicateData withName:duplicateName];

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(layoutUndoController:didChangeModelNamed:wasCreate:)]) {
        [_delegate layoutUndoController:self didChangeModelNamed:duplicateName wasCreate:YES];
    }
}

#pragma mark - Model Property Operations

- (void)registerPropertyChange:(NSString *)modelName
                           key:(NSString *)key
                      oldValue:(id)oldValue
                      newValue:(id)newValue {
    if (!modelName || !key) {
        return;
    }

    // Check if actually changed
    if ((oldValue == nil && newValue == nil) ||
        ([oldValue isEqual:newValue])) {
        return;
    }

    NSDictionary *info = @{
        @"modelName": modelName,
        @"key": key,
        @"oldValue": oldValue ?: [NSNull null],
        @"newValue": newValue ?: [NSNull null]
    };

    [[_undoManager prepareWithInvocationTarget:self]
        restoreProperty:info isUndo:YES];

    [_undoManager setActionName:[NSString stringWithFormat:@"Change %@", key]];
}

- (void)restoreProperty:(NSDictionary *)info isUndo:(BOOL)isUndo {
    NSString *modelName = info[@"modelName"];
    NSString *key = info[@"key"];
    id targetValue = isUndo ? info[@"oldValue"] : info[@"newValue"];

    if (!modelName || !key || !_engineBridge) {
        return;
    }

    // Convert NSNull back to nil
    if ([targetValue isKindOfClass:[NSNull class]]) {
        targetValue = nil;
    }

    // Register opposite action
    [[_undoManager prepareWithInvocationTarget:self]
        restoreProperty:info isUndo:!isUndo];

    // Apply the property change
    [_engineBridge updateModelProperty:modelName key:key value:targetValue];

    // Notify delegate
    if ([_delegate respondsToSelector:@selector(layoutUndoController:didRestoreModelNamed:)]) {
        [_delegate layoutUndoController:self didRestoreModelNamed:modelName];
    }
}

#pragma mark - Helper Methods

- (NSDictionary *)dictionaryFromSnapshot:(XLModelTransformSnapshot)snapshot
                               modelName:(NSString *)modelName {
    return @{
        @"modelName": modelName ?: @"",
        @"posX": @(snapshot.position.x),
        @"posY": @(snapshot.position.y),
        @"posZ": @(snapshot.position.z),
        @"scaleX": @(snapshot.scale.x),
        @"scaleY": @(snapshot.scale.y),
        @"scaleZ": @(snapshot.scale.z),
        @"rotX": @(snapshot.rotation.x),
        @"rotY": @(snapshot.rotation.y),
        @"rotZ": @(snapshot.rotation.z),
    };
}

- (XLModelTransformSnapshot)snapshotFromDictionary:(NSDictionary *)dict {
    XLModelTransformSnapshot snapshot;
    snapshot.position = simd_make_float3(
        [dict[@"posX"] floatValue],
        [dict[@"posY"] floatValue],
        [dict[@"posZ"] floatValue]
    );
    snapshot.scale = simd_make_float3(
        [dict[@"scaleX"] floatValue],
        [dict[@"scaleY"] floatValue],
        [dict[@"scaleZ"] floatValue]
    );
    snapshot.rotation = simd_make_float3(
        [dict[@"rotX"] floatValue],
        [dict[@"rotY"] floatValue],
        [dict[@"rotZ"] floatValue]
    );
    return snapshot;
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
    }
}

- (void)redo {
    if ([_undoManager canRedo]) {
        [_undoManager redo];
    }
}

- (void)clearUndoHistory {
    [_undoManager removeAllActions];
    _hasCapture = NO;
}

#pragma mark - Undo Grouping

- (void)beginUndoGroup:(NSString *)actionName {
    [_undoManager beginUndoGrouping];
    if (actionName.length > 0) {
        [_undoManager setActionName:actionName];
    }
}

- (void)endUndoGroup {
    [_undoManager endUndoGrouping];
}

@end

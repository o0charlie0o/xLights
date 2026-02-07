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

@class XLModelPropertiesView;
@class XLEngineBridge;

/// Delegate protocol for model property changes.
@protocol XLModelPropertiesDelegate <NSObject>
@optional
- (void)modelProperties:(XLModelPropertiesView *)view
       didChangeProperty:(NSString *)key
                   value:(id)value
                forModel:(NSString *)modelName;
- (void)modelPropertiesDidRequestEditCustomModel:(XLModelPropertiesView *)view
                                        forModel:(NSString *)modelName;
@end

/// Displays editable model properties in a vertical stack of disclosure sections.
///
/// Sections: General, Model Type, String Properties, Position & Size, Controller, Appearance.
/// The Model Type section dynamically changes its contents depending on the selected
/// model's type (e.g. Matrix, Tree, Arches, Single Line, Star, Circle, Icicles, Custom).
/// Supports single-model and multi-model (mixed state) editing.
@interface XLModelPropertiesView : NSView

@property (nonatomic, weak) id<XLModelPropertiesDelegate> delegate;
@property (nonatomic, weak) XLEngineBridge *engineBridge;

/// Load properties for a single model.
- (void)showPropertiesForModel:(NSString *)modelName info:(NSDictionary *)modelInfo;

/// Show properties for multiple selected models (show shared properties, mixed state).
- (void)showPropertiesForModels:(NSArray<NSString *> *)modelNames infos:(NSArray<NSDictionary *> *)modelInfos;

/// Clear all properties.
- (void)clearProperties;

@end

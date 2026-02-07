/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#import "XLControllerDefinitionLoader.h"

#pragma mark - XLControllerVariantInfo

@implementation XLControllerVariantInfo

- (instancetype)init {
    self = [super init];
    if (self) {
        _name = @"";
        _maxPixelPort = 0;
        _maxSerialPort = 0;
        _maxPixelPortChannels = 0;
        _maxSerialPortChannels = 0;
        _maxInputUniverses = 0;
        _supportsUpload = NO;
        _supportsInputOnlyUpload = NO;
        _supportsAutoLayout = NO;
        _supportsSmartRemotes = NO;
        _pixelProtocols = @[];
        _serialProtocols = @[];
        _inputProtocols = @[];
    }
    return self;
}

@end

#pragma mark - XLControllerModelInfo

@implementation XLControllerModelInfo

- (instancetype)init {
    self = [super init];
    if (self) {
        _name = @"";
        _variants = @[];
    }
    return self;
}

@end

#pragma mark - XLControllerVendorInfo

@implementation XLControllerVendorInfo

- (instancetype)init {
    self = [super init];
    if (self) {
        _name = @"";
        _models = @[];
    }
    return self;
}

@end

#pragma mark - Internal parsed XML node

/// Lightweight representation of a single XML element during parsing.
/// Used internally to build a tree of XML nodes that we can then query
/// in the same way the legacy C++ code uses wxXmlNode.
@interface _XLXmlNode : NSObject

@property (nonatomic, copy) NSString *elementName;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *attributes;
@property (nonatomic, strong) NSMutableArray<_XLXmlNode *> *children;
@property (nonatomic, copy) NSString *textContent;
@property (nonatomic, weak) _XLXmlNode *parent;

@end

@implementation _XLXmlNode

- (instancetype)init {
    self = [super init];
    if (self) {
        _elementName = @"";
        _attributes = [NSMutableDictionary dictionary];
        _children = [NSMutableArray array];
        _textContent = @"";
    }
    return self;
}

- (nullable _XLXmlNode *)childNamed:(NSString *)name {
    for (_XLXmlNode *child in _children) {
        if ([child.elementName isEqualToString:name]) {
            return child;
        }
    }
    return nil;
}

- (NSString *)childContentNamed:(NSString *)name defaultValue:(NSString *)defaultValue {
    _XLXmlNode *child = [self childNamed:name];
    if (child && child.textContent.length > 0) {
        return child.textContent;
    }
    // Check if any child has a text content by looking at grandchildren
    if (child) {
        for (_XLXmlNode *grandchild in child.children) {
            if (grandchild.textContent.length > 0) {
                return grandchild.textContent;
            }
        }
    }
    return defaultValue;
}

- (BOOL)hasChildNamed:(NSString *)name {
    return [self childNamed:name] != nil;
}

- (NSArray<NSString *> *)listContentNamed:(NSString *)parentName childName:(NSString *)childName {
    _XLXmlNode *parent = [self childNamed:parentName];
    if (!parent) return @[];

    NSMutableArray *result = [NSMutableArray array];
    for (_XLXmlNode *child in parent.children) {
        if ([child.elementName isEqualToString:childName]) {
            NSString *text = child.textContent;
            if (text.length > 0) {
                [result addObject:text];
            }
        }
    }
    return [result copy];
}

@end

#pragma mark - XML Tree Parser Delegate

/// NSXMLParser delegate that builds a tree of _XLXmlNode objects.
@interface _XLTreeParserDelegate : NSObject <NSXMLParserDelegate>

@property (nonatomic, strong) _XLXmlNode *rootNode;
@property (nonatomic, strong) _XLXmlNode *currentNode;
@property (nonatomic, strong) NSMutableString *currentText;

@end

@implementation _XLTreeParserDelegate

- (void)parser:(NSXMLParser *)parser
didStartElement:(NSString *)elementName
  namespaceURI:(nullable NSString *)namespaceURI
 qualifiedName:(nullable NSString *)qName
    attributes:(NSDictionary<NSString *, NSString *> *)attributeDict {

    _XLXmlNode *node = [[_XLXmlNode alloc] init];
    node.elementName = elementName;
    [node.attributes addEntriesFromDictionary:attributeDict];
    node.parent = _currentNode;

    if (_currentNode) {
        [_currentNode.children addObject:node];
    } else {
        _rootNode = node;
    }
    _currentNode = node;
    _currentText = [[NSMutableString alloc] init];
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    [_currentText appendString:string];
}

- (void)parser:(NSXMLParser *)parser
 didEndElement:(NSString *)elementName
  namespaceURI:(nullable NSString *)namespaceURI
 qualifiedName:(nullable NSString *)qName {

    NSString *trimmed = [_currentText stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length > 0) {
        _currentNode.textContent = trimmed;
    }
    _currentNode = _currentNode.parent;
    _currentText = [[NSMutableString alloc] init];
}

@end

#pragma mark - XLControllerDefinitionLoader

@interface XLControllerDefinitionLoader ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, XLControllerVendorInfo *> *vendorsByName;
@property (nonatomic, assign) BOOL loaded;

@end

@implementation XLControllerDefinitionLoader

+ (instancetype)sharedLoader {
    static XLControllerDefinitionLoader *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[XLControllerDefinitionLoader alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _vendorsByName = [NSMutableDictionary dictionary];
        _loaded = NO;
    }
    return self;
}

- (void)ensureLoaded {
    if (!_loaded) {
        [self loadAllControllerDefinitions];
        _loaded = YES;
    }
}

- (void)reload {
    [_vendorsByName removeAllObjects];
    _loaded = NO;
    [self ensureLoaded];
}

#pragma mark - Loading

- (void)loadAllControllerDefinitions {
    NSString *controllersDir = [self controllersDirectory];
    if (!controllersDir) {
        NSLog(@"XLControllerDefinitionLoader: controllers directory not found");
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:controllersDir error:&error];
    if (error) {
        NSLog(@"XLControllerDefinitionLoader: error listing controllers dir: %@", error);
        return;
    }

    // Filter for .xcontroller files
    NSMutableArray<NSString *> *xcontrollerFiles = [NSMutableArray array];
    for (NSString *filename in contents) {
        if ([filename.pathExtension isEqualToString:@"xcontroller"]) {
            [xcontrollerFiles addObject:[controllersDir stringByAppendingPathComponent:filename]];
        }
    }

    // Parse all files into XML trees
    NSMutableArray<_XLXmlNode *> *parsedRoots = [NSMutableArray array];
    for (NSString *filePath in xcontrollerFiles) {
        NSURL *fileURL = [NSURL fileURLWithPath:filePath];
        NSXMLParser *parser = [[NSXMLParser alloc] initWithContentsOfURL:fileURL];
        if (!parser) {
            NSLog(@"XLControllerDefinitionLoader: failed to create parser for %@", filePath);
            continue;
        }
        _XLTreeParserDelegate *delegate = [[_XLTreeParserDelegate alloc] init];
        parser.delegate = delegate;
        if ([parser parse] && delegate.rootNode) {
            [parsedRoots addObject:delegate.rootNode];
        } else {
            NSLog(@"XLControllerDefinitionLoader: failed to parse %@", filePath);
        }
    }

    // Pass 1: Collect all AbstractVariant definitions across all files
    NSMutableDictionary<NSString *, _XLXmlNode *> *abstracts = [NSMutableDictionary dictionary];
    for (_XLXmlNode *root in parsedRoots) {
        if ([root.elementName isEqualToString:@"Vendor"]) {
            NSString *vendorName = root.attributes[@"Name"] ?: @"";
            for (_XLXmlNode *child in root.children) {
                if ([child.elementName isEqualToString:@"AbstractVariant"]) {
                    NSString *varName = child.attributes[@"Name"] ?: @"";
                    NSString *key = [NSString stringWithFormat:@"%@:%@", vendorName, varName];
                    abstracts[key] = child;
                }
            }
        }
    }

    // Pass 2: Parse Controller/Variant elements with inheritance resolution
    NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSMutableArray<XLControllerVariantInfo *> *> *> *vendorData = [NSMutableDictionary dictionary];

    for (_XLXmlNode *root in parsedRoots) {
        if (![root.elementName isEqualToString:@"Vendor"]) continue;

        NSString *vendorName = root.attributes[@"Name"] ?: @"";
        if (vendorName.length == 0) continue;

        if (!vendorData[vendorName]) {
            vendorData[vendorName] = [NSMutableDictionary dictionary];
        }
        NSMutableDictionary *models = vendorData[vendorName];

        for (_XLXmlNode *child in root.children) {
            if (![child.elementName isEqualToString:@"Controller"]) continue;

            NSString *controllerName = child.attributes[@"Name"] ?: @"";
            if (controllerName.length == 0) continue;

            if (!models[controllerName]) {
                models[controllerName] = [NSMutableArray array];
            }
            NSMutableArray *variants = models[controllerName];

            for (_XLXmlNode *variantNode in child.children) {
                if (![variantNode.elementName isEqualToString:@"Variant"]) continue;

                // Resolve inheritance by merging base properties
                _XLXmlNode *resolved = [self resolveNode:variantNode abstracts:abstracts];
                XLControllerVariantInfo *info = [self variantInfoFromNode:resolved];
                info.name = variantNode.attributes[@"Name"] ?: @"";
                [variants addObject:info];
            }
        }
    }

    // Convert to final data structures
    for (NSString *vendorName in vendorData) {
        XLControllerVendorInfo *vendorInfo = [[XLControllerVendorInfo alloc] init];
        vendorInfo.name = vendorName;

        NSMutableArray<XLControllerModelInfo *> *modelInfos = [NSMutableArray array];
        NSDictionary *models = vendorData[vendorName];

        for (NSString *modelName in models) {
            XLControllerModelInfo *modelInfo = [[XLControllerModelInfo alloc] init];
            modelInfo.name = modelName;
            modelInfo.variants = models[modelName];
            [modelInfos addObject:modelInfo];
        }

        // Sort models alphabetically
        [modelInfos sortUsingComparator:^NSComparisonResult(XLControllerModelInfo *a, XLControllerModelInfo *b) {
            return [a.name localizedCaseInsensitiveCompare:b.name];
        }];
        vendorInfo.models = modelInfos;

        _vendorsByName[vendorName] = vendorInfo;
    }

    NSLog(@"XLControllerDefinitionLoader: loaded %lu vendors", (unsigned long)_vendorsByName.count);
}

- (nullable NSString *)controllersDirectory {
    // Look in the app bundle's Resources/controllers/ directory
    NSString *bundlePath = [[NSBundle mainBundle] resourcePath];
    NSString *controllersPath = [bundlePath stringByAppendingPathComponent:@"controllers"];

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:controllersPath isDirectory:&isDir] && isDir) {
        return controllersPath;
    }

    // Fallback: look relative to the executable for development builds
    NSString *execPath = [[NSBundle mainBundle] executablePath];
    NSString *execDir = [execPath stringByDeletingLastPathComponent];

    // Try ../../../controllers (for Xcode debug builds)
    NSString *devPath = [[execDir stringByAppendingPathComponent:@"../../../controllers"]
                          stringByStandardizingPath];
    if ([fm fileExistsAtPath:devPath isDirectory:&isDir] && isDir) {
        return devPath;
    }

    // Try the project root controllers directory
    devPath = [[execDir stringByAppendingPathComponent:@"../../../../controllers"]
                stringByStandardizingPath];
    if ([fm fileExistsAtPath:devPath isDirectory:&isDir] && isDir) {
        return devPath;
    }

    return nil;
}

#pragma mark - Inheritance Resolution

/// Merge properties from a base AbstractVariant into a target node.
/// Recursively resolves the base's own Base attribute if present.
- (void)mergeAbstract:(_XLXmlNode *)base
                 into:(_XLXmlNode *)target
            abstracts:(NSDictionary<NSString *, _XLXmlNode *> *)abstracts {
    if (!base) return;

    // Copy children from base that do not already exist in target
    for (_XLXmlNode *baseChild in base.children) {
        if (![target hasChildNamed:baseChild.elementName]) {
            // Deep copy the node
            _XLXmlNode *copy = [self deepCopyNode:baseChild];
            copy.parent = target;
            [target.children addObject:copy];
        }
    }

    // Recurse if the base itself has a Base attribute
    NSString *baseBase = base.attributes[@"Base"];
    if (baseBase.length > 0) {
        _XLXmlNode *parentAbstract = abstracts[baseBase];
        if (parentAbstract) {
            [self mergeAbstract:parentAbstract into:target abstracts:abstracts];
        }
    }
}

/// Resolve a Variant node by merging in all inherited AbstractVariant properties.
/// Returns a new node with all properties resolved.
- (_XLXmlNode *)resolveNode:(_XLXmlNode *)variantNode
                  abstracts:(NSDictionary<NSString *, _XLXmlNode *> *)abstracts {
    // Deep copy the variant so we don't modify the original
    _XLXmlNode *resolved = [self deepCopyNode:variantNode];

    NSString *base = variantNode.attributes[@"Base"];
    if (base.length > 0) {
        _XLXmlNode *baseNode = abstracts[base];
        if (baseNode) {
            [self mergeAbstract:baseNode into:resolved abstracts:abstracts];
        }
    }

    return resolved;
}

- (_XLXmlNode *)deepCopyNode:(_XLXmlNode *)node {
    _XLXmlNode *copy = [[_XLXmlNode alloc] init];
    copy.elementName = node.elementName;
    [copy.attributes addEntriesFromDictionary:node.attributes];
    copy.textContent = node.textContent;

    for (_XLXmlNode *child in node.children) {
        _XLXmlNode *childCopy = [self deepCopyNode:child];
        childCopy.parent = copy;
        [copy.children addObject:childCopy];
    }

    return copy;
}

#pragma mark - Node to Info Conversion

- (XLControllerVariantInfo *)variantInfoFromNode:(_XLXmlNode *)node {
    XLControllerVariantInfo *info = [[XLControllerVariantInfo alloc] init];

    info.maxPixelPort = [[node childContentNamed:@"MaxPixelPort" defaultValue:@"0"] integerValue];
    info.maxSerialPort = [[node childContentNamed:@"MaxSerialPort" defaultValue:@"0"] integerValue];
    info.maxPixelPortChannels = [[node childContentNamed:@"MaxPixelPortChannels" defaultValue:@"0"] integerValue];
    info.maxSerialPortChannels = [[node childContentNamed:@"MaxSerialPortChannels" defaultValue:@"0"] integerValue];
    info.maxInputUniverses = [[node childContentNamed:@"MaxInputUniverses" defaultValue:@"0"] integerValue];
    info.supportsUpload = [node hasChildNamed:@"SupportsUpload"] || [node hasChildNamed:@"SupportsInputOnlyUpload"];
    info.supportsInputOnlyUpload = [node hasChildNamed:@"SupportsInputOnlyUpload"];
    info.supportsAutoLayout = [node hasChildNamed:@"SupportsAutoLayout"];
    info.supportsSmartRemotes = [node hasChildNamed:@"SupportsSmartRemotes"];

    info.pixelProtocols = [node listContentNamed:@"PixelProtocols" childName:@"Protocol"];
    info.serialProtocols = [node listContentNamed:@"SerialProtocols" childName:@"Protocol"];
    info.inputProtocols = [node listContentNamed:@"InputProtocols" childName:@"Protocol"];

    return info;
}

#pragma mark - Public Query Methods

- (NSArray<NSString *> *)availableVendors {
    [self ensureLoaded];

    NSArray<NSString *> *sorted = [_vendorsByName.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return sorted;
}

- (NSArray<NSString *> *)modelsForVendor:(NSString *)vendor {
    [self ensureLoaded];

    XLControllerVendorInfo *vendorInfo = _vendorsByName[vendor];
    if (!vendorInfo) return @[];

    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (XLControllerModelInfo *model in vendorInfo.models) {
        [names addObject:model.name];
    }
    return [names copy];
}

- (NSArray<NSString *> *)variantsForVendor:(NSString *)vendor model:(NSString *)model {
    [self ensureLoaded];

    XLControllerModelInfo *modelInfo = [self modelInfoForVendor:vendor model:model];
    if (!modelInfo) return @[];

    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (XLControllerVariantInfo *variant in modelInfo.variants) {
        [names addObject:variant.name];
    }
    return [names copy];
}

- (nullable XLControllerVendorInfo *)vendorInfoForName:(NSString *)vendor {
    [self ensureLoaded];
    return _vendorsByName[vendor];
}

- (nullable XLControllerModelInfo *)modelInfoForVendor:(NSString *)vendor model:(NSString *)model {
    [self ensureLoaded];

    XLControllerVendorInfo *vendorInfo = _vendorsByName[vendor];
    if (!vendorInfo) return nil;

    for (XLControllerModelInfo *m in vendorInfo.models) {
        if ([m.name isEqualToString:model]) {
            return m;
        }
    }
    return nil;
}

- (nullable XLControllerVariantInfo *)variantInfoForVendor:(NSString *)vendor
                                                     model:(NSString *)model
                                                   variant:(NSString *)variant {
    [self ensureLoaded];

    XLControllerModelInfo *modelInfo = [self modelInfoForVendor:vendor model:model];
    if (!modelInfo) return nil;

    // If there is exactly one variant and the query variant is empty, return it
    if (modelInfo.variants.count == 1 && variant.length == 0) {
        return modelInfo.variants.firstObject;
    }

    for (XLControllerVariantInfo *v in modelInfo.variants) {
        if ([v.name isEqualToString:variant]) {
            return v;
        }
    }
    return nil;
}

- (BOOL)vendorSupportsEthernet:(NSString *)vendor {
    [self ensureLoaded];

    XLControllerVendorInfo *vendorInfo = _vendorsByName[vendor];
    if (!vendorInfo) return NO;

    static NSSet *ethernetProtocols = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ethernetProtocols = [NSSet setWithArray:@[
            @"e131", @"artnet", @"kinet", @"zcpp", @"ddp", @"opc", @"xxx ethernet", @"twinkly"
        ]];
    });

    for (XLControllerModelInfo *model in vendorInfo.models) {
        for (XLControllerVariantInfo *variant in model.variants) {
            for (NSString *protocol in variant.inputProtocols) {
                if ([ethernetProtocols containsObject:protocol.lowercaseString]) {
                    return YES;
                }
            }
        }
    }
    return NO;
}

- (BOOL)vendorSupportsSerial:(NSString *)vendor {
    [self ensureLoaded];

    XLControllerVendorInfo *vendorInfo = _vendorsByName[vendor];
    if (!vendorInfo) return NO;

    static NSSet *serialProtocols = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        serialProtocols = [NSSet setWithArray:@[
            @"dmx", @"lor", @"renard", @"opendmx", @"pixelnet",
            @"open pixelnet", @"dlight", @"lor optimised", @"xxx serial", @"ddp-input"
        ]];
    });

    for (XLControllerModelInfo *model in vendorInfo.models) {
        for (XLControllerVariantInfo *variant in model.variants) {
            for (NSString *protocol in variant.inputProtocols) {
                if ([serialProtocols containsObject:protocol.lowercaseString]) {
                    return YES;
                }
            }
        }
    }
    return NO;
}

@end

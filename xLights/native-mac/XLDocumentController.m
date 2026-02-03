#import "XLDocumentController.h"
#import "XLDocument.h"

// Error domain for XLDocumentController errors
NSString * const XLDocumentControllerErrorDomain = @"com.xlights.documentcontroller";

typedef NS_ENUM(NSInteger, XLDocumentControllerErrorCode) {
    XLDocumentControllerErrorFileNotFound = 1001,
    XLDocumentControllerErrorInvalidShowFolder = 1002,
    XLDocumentControllerErrorUnsupportedFileType = 1003,
    XLDocumentControllerErrorPermissionDenied = 1004,
};

@implementation XLDocumentController

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        // Register for launch services
        // This enables drag-and-drop onto dock icon
    }
    return self;
}

#pragma mark - Opening Documents

- (void)openShowFolder:(NSURL *)url completionHandler:(void (^)(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error))completionHandler {
    // Validate URL
    if (!url) {
        if (completionHandler) {
            NSError *error = [NSError errorWithDomain:XLDocumentControllerErrorDomain
                                                 code:XLDocumentControllerErrorFileNotFound
                                             userInfo:@{NSLocalizedDescriptionKey: @"No URL provided"}];
            completionHandler(nil, NO, error);
        }
        return;
    }

    // Check if path exists
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDirectory]) {
        if (completionHandler) {
            NSError *error = [NSError errorWithDomain:XLDocumentControllerErrorDomain
                                                 code:XLDocumentControllerErrorFileNotFound
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Path not found: %@", url.path],
                                                        NSURLErrorKey: url}];
            completionHandler(nil, NO, error);
        }
        return;
    }

    // Validate it's actually a show folder
    if (isDirectory) {
        NSURL *rgbEffectsURL = [url URLByAppendingPathComponent:@"xlights_rgbeffects.xml"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:rgbEffectsURL.path]) {
            if (completionHandler) {
                NSError *error = [NSError errorWithDomain:XLDocumentControllerErrorDomain
                                                     code:XLDocumentControllerErrorInvalidShowFolder
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Selected folder is not a valid xLights show folder (missing xlights_rgbeffects.xml)",
                                                            NSURLErrorKey: url}];
                completionHandler(nil, NO, error);
            }
            return;
        }
    }

    // Check if this show folder is already open
    for (NSDocument *doc in self.documents) {
        if ([doc isKindOfClass:[XLDocument class]]) {
            XLDocument *xlDoc = (XLDocument *)doc;
            if ([xlDoc.showFolderURL isEqual:url]) {
                // Already open - bring to front
                if (completionHandler) {
                    completionHandler(doc, YES, nil);
                }
                return;
            }
        }
    }

    // Open as new document
    [self openDocumentWithContentsOfURL:url
                                display:YES
                      completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error) {
        if (completionHandler) {
            completionHandler(document, documentWasAlreadyOpen, error);
        }
    }];
}

- (void)presentOpenPanelWithCompletionHandler:(void (^)(NSArray<NSURL *> *urls))completionHandler {
    NSOpenPanel *panel = [NSOpenPanel openPanel];

    panel.title = @"Open xLights Sequence or Show Folder";
    panel.message = @"Select a sequence file (.xlights, .fseq) or a show folder";
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.treatsFilePackagesAsDirectories = NO;

    // File types we support
    panel.allowedFileTypes = @[@"xlights", @"xsq", @"xml", @"fseq"];

    // Custom validation to allow show folders
    panel.delegate = (id<NSOpenSavePanelDelegate>)self;

    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            if (completionHandler) {
                completionHandler(panel.URLs);
            }
        } else {
            if (completionHandler) {
                completionHandler(@[]);
            }
        }
    }];
}

#pragma mark - NSOpenSavePanelDelegate

- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url {
    // Allow all files and directories
    NSNumber *isDirectory = nil;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];

    if (isDirectory && [isDirectory boolValue]) {
        // Check if this is a show folder
        NSURL *rgbEffectsURL = [url URLByAppendingPathComponent:@"xlights_rgbeffects.xml"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:rgbEffectsURL.path]) {
            return YES; // Valid show folder
        }

        // Allow navigation into directories
        return YES;
    }

    // Check file extension
    NSString *ext = url.pathExtension.lowercaseString;
    return [ext isEqualToString:@"xlights"] ||
           [ext isEqualToString:@"xsq"] ||
           [ext isEqualToString:@"xml"] ||
           [ext isEqualToString:@"fseq"];
}

#pragma mark - NSDocumentController Overrides

- (NSString *)typeForContentsOfURL:(NSURL *)url error:(NSError **)outError {
    // Determine document type based on URL

    NSNumber *isDirectory = nil;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];

    if (isDirectory && [isDirectory boolValue]) {
        // Check if this is a show folder
        NSURL *rgbEffectsURL = [url URLByAppendingPathComponent:@"xlights_rgbeffects.xml"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:rgbEffectsURL.path]) {
            return @"Show Folder";
        }
    }

    // Check file extension
    NSString *ext = url.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"fseq"]) {
        return @"FSEQ Sequence";
    } else if ([ext isEqualToString:@"xlights"] || [ext isEqualToString:@"xsq"] || [ext isEqualToString:@"xml"]) {
        return @"xLights Sequence";
    }

    return [super typeForContentsOfURL:url error:outError];
}

- (Class)documentClassForType:(NSString *)typeName {
    // All types use XLDocument
    if ([typeName isEqualToString:@"xLights Sequence"] ||
        [typeName isEqualToString:@"FSEQ Sequence"] ||
        [typeName isEqualToString:@"Show Folder"]) {
        return [XLDocument class];
    }

    return [super documentClassForType:typeName];
}

- (NSArray *)fileExtensionsFromType:(NSString *)typeName {
    if ([typeName isEqualToString:@"xLights Sequence"]) {
        return @[@"xlights", @"xsq", @"xml"];
    } else if ([typeName isEqualToString:@"FSEQ Sequence"]) {
        return @[@"fseq"];
    } else if ([typeName isEqualToString:@"Show Folder"]) {
        return @[]; // Directories don't have extensions
    }

    return [super fileExtensionsFromType:typeName];
}

#pragma mark - Recent Files

- (void)noteNewRecentDocumentURL:(NSURL *)url {
    // Filter out temporary files and autosaves
    if ([url.path containsString:@"/Autosaved/"] ||
        [url.path containsString:@"/Temp/"] ||
        [url.lastPathComponent hasPrefix:@"."]) {
        return;
    }

    [super noteNewRecentDocumentURL:url];
}

#pragma mark - Drag and Drop Support

- (void)openDocumentWithContentsOfURL:(NSURL *)url
                              display:(BOOL)displayDocument
                    completionHandler:(void (^)(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error))completionHandler {
    // Check if this is a show folder
    NSNumber *isDirectory = nil;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];

    if (isDirectory && [isDirectory boolValue]) {
        NSURL *rgbEffectsURL = [url URLByAppendingPathComponent:@"xlights_rgbeffects.xml"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:rgbEffectsURL.path]) {
            // This is a show folder - open it
            [self openShowFolder:url completionHandler:completionHandler];
            return;
        }
    }

    // Normal file opening
    [super openDocumentWithContentsOfURL:url
                                 display:displayDocument
                       completionHandler:completionHandler];
}

@end

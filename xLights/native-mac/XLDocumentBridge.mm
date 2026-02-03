#import "XLDocumentBridge.h"
#import "XLDocument.h"
#import "XLDocumentController.h"
#import <map>
#import <mutex>

// Storage for frame → document associations
static std::map<xLightsFrame*, XLDocument*> s_documentMap;
static std::mutex s_documentMapMutex;

void XLDocumentBridge::setCurrentDocument(xLightsFrame* frame, void* document) {
    std::lock_guard<std::mutex> lock(s_documentMapMutex);

    XLDocument* doc = (__bridge XLDocument*)document;
    s_documentMap[frame] = doc;

    // Wire up the SequenceEngine to the document
    // (In full integration, we'd get the engine from the frame)
}

void* XLDocumentBridge::getCurrentDocument(xLightsFrame* frame) {
    std::lock_guard<std::mutex> lock(s_documentMapMutex);

    auto it = s_documentMap.find(frame);
    if (it != s_documentMap.end()) {
        return (__bridge void*)it->second;
    }
    return nullptr;
}

void XLDocumentBridge::updateDocumentDirtyState(xLightsFrame* frame, bool isDirty) {
    std::lock_guard<std::mutex> lock(s_documentMapMutex);

    auto it = s_documentMap.find(frame);
    if (it != s_documentMap.end()) {
        XLDocument* doc = it->second;
        dispatch_async(dispatch_get_main_queue(), ^{
            [doc updateChangeCount:isDirty ? NSChangeDone : NSChangeCleared];
        });
    }
}

void XLDocumentBridge::notifySequenceLoaded(xLightsFrame* frame, const std::string& path) {
    NSURL* url = [NSURL fileURLWithPath:@(path.c_str())];

    dispatch_async(dispatch_get_main_queue(), ^{
        NSDocumentController* controller = [NSDocumentController sharedDocumentController];
        [controller noteNewRecentDocumentURL:url];
    });
}

void XLDocumentBridge::notifySequenceSaved(xLightsFrame* frame, const std::string& path) {
    std::lock_guard<std::mutex> lock(s_documentMapMutex);

    auto it = s_documentMap.find(frame);
    if (it != s_documentMap.end()) {
        XLDocument* doc = it->second;
        dispatch_async(dispatch_get_main_queue(), ^{
            [doc updateChangeCount:NSChangeCleared];
        });
    }

    // Also update recent files
    notifySequenceLoaded(frame, path);
}

void* XLDocumentBridge::createDocument(const std::string& path) {
    NSURL* url = [NSURL fileURLWithPath:@(path.c_str())];

    __block XLDocument* doc = nil;

    dispatch_sync(dispatch_get_main_queue(), ^{
        NSDocumentController* controller = [NSDocumentController sharedDocumentController];
        [controller openDocumentWithContentsOfURL:url
                                          display:YES
                                completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error) {
            if (document && [document isKindOfClass:[XLDocument class]]) {
                doc = (XLDocument*)document;
            } else if (error) {
                NSLog(@"Error opening document: %@", error);
            }
        }];
    });

    return (__bridge_retained void*)doc;
}

void XLDocumentBridge::closeDocument(xLightsFrame* frame) {
    std::lock_guard<std::mutex> lock(s_documentMapMutex);

    auto it = s_documentMap.find(frame);
    if (it != s_documentMap.end()) {
        XLDocument* doc = it->second;
        dispatch_async(dispatch_get_main_queue(), ^{
            [doc close];
        });
        s_documentMap.erase(it);
    }
}

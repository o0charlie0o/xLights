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

// XLDocumentBridge: C++ interface for integrating XLDocument with xLightsFrame.
//
// This header provides a C++ API that the existing wxWidgets code can use
// to interact with the NSDocument-based file handling system. It bridges
// between the Objective-C++ world (XLDocument) and the pure C++ world
// (xLightsFrame, SequenceEngine).
//
// Usage from xLightsFrame:
//   XLDocumentBridge::setCurrentDocument(frame, document);
//   XLDocumentBridge::updateDocumentDirtyState(frame, isDirty);

#ifdef __OBJC__
@class XLDocument;
#else
class XLDocument;
#endif

class xLightsFrame;

namespace xlEngine {
    class SequenceEngine;
}

/// Bridge between XLDocument (Objective-C++) and xLightsFrame (C++).
class XLDocumentBridge {
public:
    /// Associate an XLDocument with an xLightsFrame.
    /// This allows the document to call back into the frame for loading/saving.
    static void setCurrentDocument(xLightsFrame* frame, void* document);

    /// Get the current XLDocument associated with a frame.
    /// Returns nullptr if no document is set.
    static void* getCurrentDocument(xLightsFrame* frame);

    /// Update the dirty state of the current document.
    /// This controls the unsaved changes dot in the close button.
    static void updateDocumentDirtyState(xLightsFrame* frame, bool isDirty);

    /// Notify the document that a sequence was loaded.
    /// This updates the Recent Files menu.
    static void notifySequenceLoaded(xLightsFrame* frame, const std::string& path);

    /// Notify the document that a sequence was saved.
    static void notifySequenceSaved(xLightsFrame* frame, const std::string& path);

    /// Create a new XLDocument for a given URL.
    /// Returns an opaque pointer to XLDocument* (must be cast back in ObjC++ code).
    static void* createDocument(const std::string& path);

    /// Close the current document.
    static void closeDocument(xLightsFrame* frame);
};

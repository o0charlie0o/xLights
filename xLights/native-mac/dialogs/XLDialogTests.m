/***************************************************************
 * Name:      XLDialogTests.m
 * Purpose:   Test/demonstration code for native macOS dialogs
 * Author:    xLights Team
 * Created:   2026-02-03
 * Copyright: xLights (https://xlights.org)
 * License:   GPLv3
 *
 * This file is not compiled into the application. It serves as
 * a reference implementation and can be used for manual testing.
 **************************************************************/

#import "XLNativeDialogs.h"

// Uncomment to enable test code compilation
#ifdef XL_DIALOG_TESTS_ENABLED

@interface XLDialogTestRunner : NSObject
+ (void)runAllTests:(NSWindow *)parentWindow;
@end

@implementation XLDialogTestRunner

+ (void)runAllTests:(NSWindow *)parentWindow {
    // Test 1: Basic Alert
    [self testBasicAlert:parentWindow];

    // Test 2: Confirmation Dialog
    [self testConfirmation:parentWindow];

    // Test 3: Text Input
    [self testTextInput:parentWindow];

    // Test 4: File Open Panel
    [self testFileOpen:parentWindow];

    // Test 5: File Save Panel
    [self testFileSave:parentWindow];

    // Test 6: Directory Panel
    [self testDirectoryPanel:parentWindow];

    // Test 7: Single Choice
    [self testSingleChoice:parentWindow];

    // Test 8: Multi Choice
    [self testMultiChoice:parentWindow];

    // Test 9: Number Entry
    [self testNumberEntry:parentWindow];

    // Test 10: Progress Dialog
    [self testProgress:parentWindow];

    // Test 11: Save Changes Dialog
    [self testSaveChanges:parentWindow];

    NSLog(@"All dialog tests completed!");
}

+ (void)testBasicAlert:(NSWindow *)parent {
    NSLog(@"Testing basic alert...");

    // Test informational alert
    [XLNativeDialogs showInfoWithTitle:@"Information"
                               message:@"This is an informational message."
                          parentWindow:parent];

    // Test warning alert
    [XLNativeDialogs showWarningWithTitle:@"Warning"
                                  message:@"This is a warning message."
                             parentWindow:parent];

    // Test error alert
    [XLNativeDialogs showErrorWithTitle:@"Error"
                                message:@"This is an error message."
                           parentWindow:parent];

    NSLog(@"Basic alert tests passed.");
}

+ (void)testConfirmation:(NSWindow *)parent {
    NSLog(@"Testing confirmation dialogs...");

    // Test Yes/No
    BOOL result = [XLNativeDialogs showConfirmationWithTitle:@"Confirm"
                                                     message:@"Do you want to continue?"
                                                parentWindow:parent];
    NSLog(@"Yes/No result: %@", result ? @"Yes" : @"No");

    // Test Yes/No/Cancel
    XLAlertResult cancelResult = [XLNativeDialogs showConfirmationWithCancelTitle:@"Save Changes"
                                                                          message:@"Do you want to save?"
                                                                     parentWindow:parent];
    NSString *resultStr;
    switch (cancelResult) {
        case XLAlertResultYes: resultStr = @"Yes"; break;
        case XLAlertResultNo: resultStr = @"No"; break;
        case XLAlertResultCancel: resultStr = @"Cancel"; break;
        default: resultStr = @"Unknown"; break;
    }
    NSLog(@"Yes/No/Cancel result: %@", resultStr);

    NSLog(@"Confirmation tests passed.");
}

+ (void)testTextInput:(NSWindow *)parent {
    NSLog(@"Testing text input dialogs...");

    // Basic text input
    NSString *text = [XLNativeDialogs showTextInputWithTitle:@"Enter Name"
                                                     message:@"Please enter your name:"
                                                defaultValue:@"John Doe"
                                                 placeholder:@"Full name"
                                                parentWindow:parent];
    if (text) {
        NSLog(@"Text entered: %@", text);
    } else {
        NSLog(@"Text input cancelled");
    }

    // Secure text input
    NSString *password = [XLNativeDialogs showSecureTextInputWithTitle:@"Enter Password"
                                                               message:@"Please enter your password:"
                                                           placeholder:@"Password"
                                                          parentWindow:parent];
    if (password) {
        NSLog(@"Password entered (length: %lu)", (unsigned long)password.length);
    } else {
        NSLog(@"Password input cancelled");
    }

    NSLog(@"Text input tests passed.");
}

+ (void)testFileOpen:(NSWindow *)parent {
    NSLog(@"Testing file open panel...");

    // Single file
    NSArray<NSURL *> *files = [XLNativeDialogs showOpenPanelWithTitle:@"Open Sequence"
                                                           directory:nil
                                                           fileTypes:@[@"xlights", @"xsq"]
                                                       allowMultiple:NO
                                                        parentWindow:parent];
    if (files.count > 0) {
        NSLog(@"Selected file: %@", files.firstObject.path);
    } else {
        NSLog(@"File open cancelled");
    }

    // Multiple files
    NSArray<NSURL *> *multiFiles = [XLNativeDialogs showOpenPanelWithTitle:@"Select Multiple Files"
                                                                directory:nil
                                                                fileTypes:nil
                                                            allowMultiple:YES
                                                             parentWindow:parent];
    NSLog(@"Selected %lu files", (unsigned long)multiFiles.count);

    NSLog(@"File open tests passed.");
}

+ (void)testFileSave:(NSWindow *)parent {
    NSLog(@"Testing file save panel...");

    NSURL *saveURL = [XLNativeDialogs showSavePanelWithTitle:@"Save Sequence"
                                                  directory:nil
                                                defaultName:@"NewSequence.xlights"
                                                  fileTypes:@[@"xlights"]
                                               parentWindow:parent];
    if (saveURL) {
        NSLog(@"Save location: %@", saveURL.path);
    } else {
        NSLog(@"File save cancelled");
    }

    NSLog(@"File save tests passed.");
}

+ (void)testDirectoryPanel:(NSWindow *)parent {
    NSLog(@"Testing directory panel...");

    NSURL *dirURL = [XLNativeDialogs showDirectoryPanelWithTitle:@"Select Folder"
                                                      directory:nil
                                           canCreateDirectories:YES
                                                   parentWindow:parent];
    if (dirURL) {
        NSLog(@"Selected directory: %@", dirURL.path);
    } else {
        NSLog(@"Directory selection cancelled");
    }

    NSLog(@"Directory panel tests passed.");
}

+ (void)testSingleChoice:(NSWindow *)parent {
    NSLog(@"Testing single choice dialog...");

    NSArray<NSString *> *choices = @[@"Option A", @"Option B", @"Option C", @"Option D"];
    NSInteger selection = [XLNativeDialogs showSingleChoiceWithTitle:@"Select Option"
                                                             message:@"Choose one option:"
                                                             choices:choices
                                                    defaultSelection:1
                                                        parentWindow:parent];
    if (selection >= 0) {
        NSLog(@"Selected: %@ (index %ld)", choices[selection], (long)selection);
    } else {
        NSLog(@"Single choice cancelled");
    }

    NSLog(@"Single choice tests passed.");
}

+ (void)testMultiChoice:(NSWindow *)parent {
    NSLog(@"Testing multi-choice dialog...");

    NSArray<NSString *> *choices = @[@"Red", @"Green", @"Blue", @"Yellow", @"Orange"];
    NSArray<NSNumber *> *initial = @[@(0), @(2)]; // Red and Blue pre-selected

    NSArray<NSNumber *> *selections = [XLNativeDialogs showMultiChoiceWithTitle:@"Select Colors"
                                                                        message:@"Choose your favorite colors:"
                                                                        choices:choices
                                                             initialSelections:initial
                                                                   parentWindow:parent];
    if (selections) {
        NSMutableArray *selected = [NSMutableArray array];
        for (NSNumber *idx in selections) {
            [selected addObject:choices[idx.integerValue]];
        }
        NSLog(@"Selected: %@", [selected componentsJoinedByString:@", "]);
    } else {
        NSLog(@"Multi-choice cancelled");
    }

    NSLog(@"Multi-choice tests passed.");
}

+ (void)testNumberEntry:(NSWindow *)parent {
    NSLog(@"Testing number entry dialog...");

    NSInteger value;
    BOOL ok = [XLNativeDialogs showNumberEntryWithTitle:@"Enter Count"
                                                message:@"How many items?"
                                                 prompt:@"Count:"
                                                  value:10
                                                    min:1
                                                    max:100
                                           parentWindow:parent
                                               outValue:&value];
    if (ok) {
        NSLog(@"Number entered: %ld", (long)value);
    } else {
        NSLog(@"Number entry cancelled");
    }

    NSLog(@"Number entry tests passed.");
}

+ (void)testProgress:(NSWindow *)parent {
    NSLog(@"Testing progress dialog...");

    XLProgressController *progress = [XLNativeDialogs showProgressWithTitle:@"Processing"
                                                                    message:@"Please wait..."
                                                                    maximum:100
                                                                  canCancel:YES
                                                               parentWindow:parent];

    // Simulate work
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (int i = 0; i <= 100; i++) {
            if (progress.wasCancelled) {
                NSLog(@"Progress cancelled at %d%%", i);
                break;
            }

            dispatch_sync(dispatch_get_main_queue(), ^{
                [progress updateProgress:i
                                 message:[NSString stringWithFormat:@"Processing item %d...", i]];
            });

            [NSThread sleepForTimeInterval:0.05];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [progress close];
            NSLog(@"Progress completed.");
        });
    });
}

+ (void)testSaveChanges:(NSWindow *)parent {
    NSLog(@"Testing save changes dialog...");

    NSInteger result = [XLNativeDialogs showSaveChangesDialogForDocument:@"MySequence.xlights"
                                                            parentWindow:parent];
    NSString *action;
    switch (result) {
        case 1: action = @"Save"; break;
        case 0: action = @"Don't Save"; break;
        case -1: action = @"Cancel"; break;
        default: action = @"Unknown"; break;
    }
    NSLog(@"Save changes result: %@", action);

    NSLog(@"Save changes tests passed.");
}

@end

#endif // XL_DIALOG_TESTS_ENABLED

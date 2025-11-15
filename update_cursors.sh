#!/bin/bash
# Helper script to clean cursor PNG files after editing

echo "Removing extended attributes from cursor files..."
xattr -c include/cursor_brightness.png 2>/dev/null
xattr -c include/cursor_fade.png 2>/dev/null

echo "Cursor files cleaned successfully!"
echo "You can now rebuild in Xcode."

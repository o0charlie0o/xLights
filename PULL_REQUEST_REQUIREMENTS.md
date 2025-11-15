# xLights Pull Request Guidelines

Based on analysis of recent PRs from core contributors (derwin12, computergeek1507, dkulp) and CONTRIBUTING.md guidelines.

## PR Title Format

**Keep titles concise and descriptive:**
- Start with action verb (Add, Fix, Update, Handle, Correct, etc.)
- Describe what was done, not how
- Reference issue number at end if applicable

**Examples:**
```
✅ Add confirmation dialog for viewpoint deletion
✅ Fix crash with duplicate effect #5633
✅ Handle alpha channel in Image #5456
✅ Use a copy of css for check sequence #5502
✅ Vertical text was off screen #5578
```

**Avoid:**
```
❌ Added some changes to viewpoint stuff
❌ Fixed a bug
❌ Updates
```

## PR Description Format

### Minimal but Clear

The xLights project favors **concise, focused descriptions**. Most PRs have 1-3 sentence descriptions.

### Standard Format

```markdown
[1-2 sentence problem statement]. #[issue-number]
```

**Examples from actual PRs:**

```markdown
Only if you ack and actually delete the group, should you loop back thru to check again. #5652
```

```markdown
The duplicate effect was built to be used on the model. It is causing crash when used on strands and nodes.
```

```markdown
States would import and appear n times in the rgbeffects file, once for each state defined.
So four states would appear in the file as A,A,B,A,B,C,A,B,C,D.
#5496
```

### When to Add Screenshots

Include screenshots for **UI changes only**:

```markdown
A better (first) view of the restore backup dialog. Originally it would not show the other two columns and only the dates.

<img width="934" height="595" alt="image" src="https://github.com/user-attachments/assets/607538d4-5691-4508-828d-10291bbeded5" />
```

### When to Add Implementation Notes

Add brief notes only if there's:
- Platform-specific concerns
- Testing needed on other platforms
- Questions for reviewers
- Multiple commits with different purposes

**Example:**
```markdown
To avoid permission problems, use a copy of the css file placed in the show folder for the check sequence. Remove the css along with the .html when xlights closes. #5502

(todo - test on mac build)
```

**Example with reviewer question:**
```markdown
@computergeek1507 Scott, is this what we need here - seems to work.
```

**Example with multi-commit explanation:**
```markdown
Two commits:
First one is to add some files and fix a few minor things to allow a 32-bit OSX build. It's a work in progress (works on my machine) :-)

Second is to add the ability to use hlsIdata files as a source for conversions on the convert tab.
```

## What NOT to Include

### ❌ Don't Include:
1. **Detailed bullet-point change lists** - The code diff shows this
2. **Line-by-line explanations** - Reviewers can read code
3. **Attribution footers** - Git tracks authorship
4. **Excessive formatting** - Keep it simple
5. **Implementation details** - Unless necessary for understanding

### ❌ Bad Example (Too Verbose):
```markdown
Add confirmation dialog for viewpoint deletion

Prevents accidental deletion of 3D and 2D viewpoints by requiring
user confirmation before deletion. Addresses user feedback about
accidentally clicking "Delete Viewpoint" when intending to click
"Load Viewpoint".

Changes:
- Added wxMessageBox confirmation dialog before deleting 3D viewpoints
- Added wxMessageBox confirmation dialog before deleting 2D viewpoints
- Dialog shows viewpoint name and warns action cannot be undone
- Uses wxYES_NO with wxNO_DEFAULT to prevent accidental confirmation
- Displays appropriate icon (wxICON_QUESTION) for confirmation prompt

Location: xLights/LayoutPanel.cpp
- Line 5158-5165: 3D viewpoint deletion confirmation
- Line 5175-5182: 2D viewpoint deletion confirmation

Testing:
- Verified confirmation appears
- Verified "No" cancels
- Verified "Yes" proceeds

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>
```

### ✅ Good Example (Concise):
```markdown
Prevents accidental deletion of 3D and 2D viewpoints by requiring user confirmation before deletion. #5XXX
```

Or with a bit more context:
```markdown
Users accidentally delete viewpoints when clicking near "Load Viewpoint" button. Added confirmation dialog before deleting 3D/2D viewpoints. #5XXX
```

## Issue References

**Always reference the GitHub issue number:**
- Use `#` followed by issue number
- Place at end of description typically
- Can be in title if appropriate

**Examples:**
```
Fix crash with duplicate effect #5633
Handle alpha channel in Image #5456
Use a copy of css for check sequence #5502
```

## Before Submitting

### Pre-Submission Checklist

- [ ] **Title is clear and concise** (action verb + what was done)
- [ ] **Description explains the problem** (1-3 sentences)
- [ ] **Issue number referenced** (if applicable)
- [ ] **Screenshots included** (only for UI changes)
- [ ] **Code tested** (verify it works)
- [ ] **No unnecessary comments** (let code speak)
- [ ] **Consistent with surrounding code style**
- [ ] **Changes are focused** (no unrelated refactoring)
- [ ] **Community value** (benefits broader community, not just personal use)

### Testing Notes

If there are platform-specific concerns, add a brief note:
```markdown
(todo - test on mac build)
```

Or if you've tested specific scenarios:
```markdown
Tested with lines, stars and polys just to verify.
```

## Common PR Patterns

### Bug Fix
```markdown
[What was broken]. [Optional: how it manifested]. #[issue]
```
Example: `The duplicate effect was built to be used on the model. It is causing crash when used on strands and nodes.`

### Feature Addition
```markdown
[Brief description of feature]. #[issue]
```
Example: `Add ability to import HLS hlsIdata files`

### UI Improvement
```markdown
[What was wrong with UI]. [Optional: screenshot of before/after]. #[issue]
```
Example: `The color swatch area was too small and truncated off. #5579`

### Crash Fix
```markdown
[What caused crash]. #[issue]
```
Example: `A crash occurs if a MH preset is loaded or created that does not have a path defined. #5507`

### Behavior Correction
```markdown
[What was happening incorrectly]. [What should happen]. #[issue]
```
Example: `States would import and appear n times in the rgbeffects file, once for each state defined. So four states would appear in the file as A,A,B,A,B,C,A,B,C,D. #5496`

## Real-World Examples

### Excellent Examples from Core Contributors

**Minimal and clear:**
```markdown
Title: Catch crash with duplicate effect #5633
Body: the duplicate effect was built to be used on the model. It is causing crash when used on strands and nodes.
```

**With brief context:**
```markdown
Title: Use a copy of css for check sequence #5502
Body: To avoid permission problems, use a copy of the css file placed in the show folder for the check sequence. Remove the css along with the .html when xlights closes. #5502

(todo - test on mac build)
```

**UI change with screenshot:**
```markdown
Title: Show dates of the newer autosave rgb file #5532
Body: Show the dates of the files so you can make a better decision when a newer rgbeffects file is found. #5532

(ignore dates - forced it to show the message during the test to grab a screen shot)
<img width="367" height="263" alt="image" src="..." />
```

**Simple one-liner:**
```markdown
Title: Dont upscale the images #5604
Body: 2025.08 introduced an arbitrary upscaling of the images. This reverses that. #5604.
```

**With reviewer question:**
```markdown
Title: Version check with 3rd digit #5583
Body: @computergeek1507 Scott, is this what we need here - seems to work.
```

## Key Takeaways

1. **Be concise** - Most PR descriptions are 1-3 sentences
2. **State the problem** - What was wrong or what was needed
3. **Reference the issue** - Always use #issue-number
4. **Let code speak** - Don't explain implementation unless necessary
5. **Screenshots for UI only** - Visual changes benefit from images
6. **Test your changes** - Ensure it works before submitting
7. **Match the style** - Look at recent PRs from core contributors
8. **Focus on "why"** - Not "how" (that's what code is for)

## Questions or Concerns?

If you're unsure about your PR:
- Ask in the Facebook group or forum first
- Reference similar recent PRs
- Keep it simple and focused
- Core developers will provide feedback

Remember: The xLights team values **clear, focused contributions** over lengthy documentation. When in doubt, keep it shorter.

## Why

Clipboard users need to find saved items by category and recover accidental changes while using the keyboard. The current search key, header and permanent deletions occupy the space intended for these actions.

## What Changes

- Give the keyboard surface to a Pinyin-style category strip and full-width history rows. The disclosure expands the same categories inside the keyboard.
- Keep swipe actions, keyboard feedback and the iOS input-mode switch. A hold on a category exposes session undo and the ordinary-history clear command.
- Apply a rolling three-day window to ordinary unpinned history on new installations and on the first upgrade. Preserve subsequent retention choices.

## Capabilities

### New Capabilities

- `keyboard-organization` — Filing, browsing and session-limited undo in the keyboard.

## Impact

The keyboard extension, local history schema, self-signable packages and iOS tests are affected. An upgrade preserves recent, pinned and filed records and cleans up expired ordinary records.

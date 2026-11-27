## Why

Clipboard users need to find saved items by category and recover accidental changes while using the keyboard. The current search key, header and permanent deletions occupy the space intended for these actions.

## What Changes

- Replace keyboard history search with a scrollable category strip, expanded category list and an undo key.
- Move clear confirmation into the history area. Keep the input row, keyboard feedback and system return-key traits.
- Add cursor movement on the space bar and show a short keyboard identifier after its entry label fades.

## Capabilities

### New Capabilities

- `keyboard-organization` — Filing, browsing and session-limited undo in the keyboard.

## Impact

The keyboard extension, local history schema, self-signable packages and iOS tests are affected. Existing records must survive installation over the prior version.

## 1. Storage and lifecycle

- [x] 1.1 Add categories, filtering and atomic reversible history operations with upgrade coverage.
- [x] 1.2 Bind undo to one keyboard appearance, including dismissal, switching, and independent capture.

## 2. Keyboard interaction

- [x] 2.1 Implement host category management, the strip, expanded selector, row swipes, undo and centered clear confirmation.
- [x] 2.2 Update space, delete and system input-mode switching. Remove custom number and emoji pages and retain native return traits.

## 3. Verification and packaging

- [x] 3.1 Exercise the normal keyboard, legacy history, both signing modes and the new gestures.
- [x] 3.2 Build and verify the installable release assets and installation instructions.

The [release workflow](https://github.com/chkf/ClipBoard/actions/runs/46048896755) passed on both the independent-container and remapped App Group simulators. Both [v1.3.0 IPA downloads](https://github.com/chkf/ClipBoard/releases/tag/v1.3.0) matched their published SHA-256 checksums and contained the keyboard extension.

## 4. Switching back to ordinary history

- [x] 4.1 Preserve the ordinary page during a switch, settle a cold first read together, and keep the system input keys available during slow storage.
- [ ] 4.2 Check the first painted record and session boundaries in both signing modes, and verify the v1.3.1 installable release.

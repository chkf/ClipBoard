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
- [x] 4.2 Bind one-step undoable bulk clear to a trash-key hold, keep tap confirmation, and repeat backspace in the host field.
- [x] 4.3 Restore the original Chinese keyboard language tag and keep discovery compatible with enabled keyboards from 1.3.0.
- [x] 4.4 Check the first painted record, trash and backspace gestures, system keyboard handoff, and session boundaries in both signing modes, and verify the v1.3.1 installable release.

The first history record appeared on all 124 measured frames in light mode and all 159 in dark mode. The English system keyboard menu showed “Chinese” below Clipboard. The dark-mode test for switching to Apple's emoji keyboard passed on its second run. [Simulator results](https://github.com/chkf/ClipBoard/actions/runs/46103221599)

Both published IPA files matched their SHA-256 checksums and contained the Simplified Chinese keyboard extension. [Clipboard 1.3.1](https://github.com/chkf/ClipBoard/releases/tag/v1.3.1)

## 5. Candidate strip and full-width history

- [x] 5.1 Apply the approved category typography, fixed chevron, wrapped selection and borderless full-width history. Move clear and undo to a category hold and preserve the system switch.
- [x] 5.2 Exercise the new surface, its gestures and its visible switch on both simulator configurations.
- [ ] 5.3 Publish and verify both 1.4.0 IPA downloads.
- [ ] 5.4 Verify rolling 72-hour retention, expiry at the boundary, renewed copies, protected records and persistence of the retention selection.

Both simulator configurations inserted the short record twice at its trailing edge. The candidate strip and first history record stayed visible throughout both measured keyboard handoffs. [Simulator evidence](https://github.com/chkf/ClipBoard/actions/runs/46131177866)

## Context

One SQLite connection serves a keyboard appearance. Old installations may first open their database read-only. The private package keeps its history inside the extension.

## Decisions

- Store named categories and their memberships in additive tables. An item without a membership belongs to ordinary history. Keep capture identity and recency independent of filing.
- Count a retention day as 86,400 seconds from the last genuine copy. Exclude expired ordinary rows on read-only pages as well as during writable pruning. Filed and pinned items remain available.
- In the first writable transaction, migrate a version-zero database to a three-day window, prune using its existing pins and filing, and advance the database version. A read-only connection uses the same effective window until migration and observes later manual choices.
- Journal inverse operations inside the same SQLite transaction as each user action. Use connection-local temporary storage for deleted bodies and metadata so an image batch need not be materialized in Swift. Discard the undo session when the keyboard disappears. Automatic capture and background pruning do not create undo steps.
- Preserve native list swipes and the UIKit input-mode menu. Size the category text at 20 points by default, keep the disclosure stationary, and wrap categories in the space used by the records when expanded. History uses the full panel width and available height. A category hold opens inline actions. Clear asks for confirmation before deleting unpinned ordinary records.
- The containing app edits category names with native text fields. With a shared container it applies changes directly. A privately re-signed build delivers an individual, retryable change in a dedicated foreground text field. The user confirms the named operation in Clipboard before it takes effect. The keyboard replies with the request identifier, and the app removes that change from its saved queue. Normal launches and ordinary input fields never trigger this exchange.
- Use the system-provided globe on Face ID phones. Where UIKit requires an extension switch, provide a compact globe. Editing text, numbers and emoji belongs to the selected typing keyboard.

## Verification

Exercise upgrade and read-only behavior, deduplication, batch restore, repeated undo and dismissal. Compare the tagged package, exported screenshots and keyboard handoff against the existing iOS simulator checks.

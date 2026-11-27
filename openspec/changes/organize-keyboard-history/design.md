## Context

One SQLite connection serves a keyboard appearance. Old installations may first open their database read-only. The private package keeps its history inside the extension.

## Decisions

- Store named categories and their memberships in additive tables. An item without a membership belongs to ordinary history. Keep capture identity and recency independent of filing.
- Journal inverse operations inside the same SQLite transaction as each user action. Use connection-local temporary storage for deleted bodies and metadata so an image batch need not be materialized in Swift. Discard the undo session when the keyboard disappears. Automatic capture and background pruning do not create undo steps.
- Preserve native list swipes and the UIKit input-mode menu. Route cursor movement through the text document proxy. Category browsing and clear confirmation replace only the records area.
- The containing app edits category names with native text fields. With a shared container it applies changes directly. A privately re-signed build delivers an individual, retryable change in a dedicated foreground text field. The user confirms the named operation in Clipboard before it takes effect. The keyboard replies with the request identifier, and the app removes that change from its saved queue. Normal launches and ordinary input fields never trigger this exchange.
- Use the public system input-mode switch for numbers and emoji. A tap advances to the keyboard selected by iOS, and a hold opens the installed keyboard menu. Apple owns the layout of its numeric and emoji pages.

## Verification

Exercise upgrade and read-only behavior, deduplication, batch restore, repeated undo and dismissal. Compare the tagged package, exported screenshots and keyboard handoff against the existing iOS simulator checks.

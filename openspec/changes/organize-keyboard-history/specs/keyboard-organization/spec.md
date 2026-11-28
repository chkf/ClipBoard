## ADDED Requirements

### Requirement: Browse and file keyboard records

The keyboard SHALL open to ordinary history and present all categories in a scrollable strip. A fixed disclosure button SHALL expand a vertically scrollable list inside the keyboard. Filing SHALL require an explicit destination.

#### Scenario: File one record
- **WHEN** the user swipes a row left
- **THEN** the actions appear in physical order File, Delete, and tapping File followed by a category moves only that row
- **AND** the source category stays selected

#### Scenario: Older installation
- **WHEN** a user upgrades
- **THEN** existing records appear in ordinary history with their original content, timestamps and pins

#### Scenario: Category management and system input
- **WHEN** the user manages categories in the containing app
- **THEN** they can create, rename and remove them, with removed memberships returning to ordinary history
- **AND** the keyboard uses the system input-mode switch for Apple keyboards and emoji without presenting custom number or emoji pages
- **AND** the extension declares Simplified Chinese as its primary language so iOS can localize its language subtitle, and the containing app recognizes the previous neutral input-mode identifier during upgrades

### Requirement: Undo while the keyboard is open

The middle command SHALL undo filing, pin changes, individual deletion and clearing ordinary unpinned history in reverse order. The keyboard SHALL discard undo information when hidden or switched away.

#### Scenario: Move then delete
- **WHEN** a user files a record, deletes it in its new category and taps undo twice
- **THEN** the first tap restores the record in the destination and the second returns it to its original category

#### Scenario: Clear ordinary history
- **WHEN** the user taps the trash key and confirms the centered prompt, or holds the trash key to clear directly
- **THEN** one undo can recover the entire affected batch, and categorized or pinned entries retain their content
- **AND** holding backspace repeatedly deletes text before the host cursor and leaves the clipboard history intact

### Requirement: Keep input gestures and keyboard layout

The keyboard SHALL retain whole-key hit targets, stable input rows and the host return-key traits. Holding space and dragging SHALL move the host cursor without inserting a space. A held globe key SHALL use the system input-mode menu.

#### Scenario: Settle the space bar
- **WHEN** the keyboard has completed its entry transition
- **THEN** the centered name is replaced by a small identifier in the lower-right corner

#### Scenario: Switch back to saved history
- **WHEN** the user switches away and back to ordinary history in the same foreground app with the same access
- **THEN** the last ordinary page stays visible while the keyboard reopens its store, and an early tap inserts the current stored text once
- **AND** the first read after a cold start shows the actual categories and rows together, with input keys available independently if storage is slow
- **AND** a background transition or access change clears the retained presentation before another host or permission scope can use it

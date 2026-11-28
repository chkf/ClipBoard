## ADDED Requirements

### Requirement: Browse and file keyboard records

The keyboard SHALL open to ordinary history and present all categories in a scrollable strip. A fixed disclosure button SHALL expand a vertically scrollable list inside the keyboard. Filing SHALL require an explicit destination.

#### Scenario: File one record
- **WHEN** the user swipes a row left
- **THEN** the actions appear in physical order File, Delete, and tapping File followed by a category moves only that row
- **AND** the source category stays selected

#### Scenario: Older installation
- **WHEN** a user upgrades
- **THEN** retained records keep their original content, timestamps, pins and existing category memberships

#### Scenario: Category management and system input
- **WHEN** the user manages categories in the containing app
- **THEN** they can create, rename and remove them, with removed memberships returning to ordinary history
- **AND** the keyboard uses the system input-mode switch for Apple keyboards and emoji without presenting custom number or emoji pages
- **AND** the extension declares Simplified Chinese as its primary language so iOS can localize its language subtitle, and the containing app recognizes the previous neutral input-mode identifier during upgrades

### Requirement: Undo while the keyboard is open

Holding a category SHALL reveal commands to undo filing, pin changes, individual deletion and clearing ordinary unpinned history in reverse order. The keyboard SHALL discard undo information when hidden or switched away.

#### Scenario: Move then delete
- **WHEN** a user files a record, deletes it in its new category and taps undo twice
- **THEN** the first tap restores the record in the destination and the second returns it to its original category

#### Scenario: Clear ordinary history
- **WHEN** the user holds a category, chooses to clear ordinary history and confirms the centered prompt
- **THEN** one undo can recover the entire affected batch, and categorized or pinned entries retain their content

### Requirement: Show only categories and history on the normal keyboard surface

The category strip SHALL use 20-point text at the standard text size, horizontal scrolling and a trailing Pinyin-style chevron. History SHALL fill the surface beneath it with plain, full-width tappable records. The system switch SHALL remain accessible when UIKit requires a switch in the extension.

#### Scenario: Expand the category strip
- **WHEN** the user taps the disclosure
- **THEN** categories wrap onto additional lines, each name appears once, and the arrow points up in the same position
- **AND** selecting a category collapses the strip and shows the selected history

#### Scenario: Switch back to saved history
- **WHEN** the user switches away and back to ordinary history in the same foreground app with the same access
- **THEN** the last ordinary page stays visible while the keyboard reopens its store, and an early tap inserts the current stored text once
- **AND** the first read after a cold start shows the actual categories and rows together, with the system switch available independently if storage is slow
- **AND** a background transition or access change clears the retained presentation before another host or permission scope can use it

### Requirement: Retain recently copied ordinary records

New installations SHALL default to a rolling three-day window for ordinary unpinned history. The settings SHALL offer 3, 7, 15, 30 and 90 days. A new copy of the same content restarts the interval.

#### Scenario: Upgrade an existing keyboard
- **WHEN** an older installation first opens its history
- **THEN** the keyboard uses the three-day window, including for existing ordinary records
- **AND** its first writable migration removes expired text and images and preserves pins, filing, other preferences and the latest copy event
- **AND** a duration selected after migration is retained on subsequent launches

#### Scenario: Reach the three-day boundary
- **WHEN** a record's last effective copy reaches 72 hours in three-day mode
- **THEN** ordinary unpinned text and images disappear from the keyboard, including when its database is read-only
- **AND** the next writable cleanup deletes expired records, originals and thumbnails, and preserves pinned and filed items

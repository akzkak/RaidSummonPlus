# RaidSummonPlus

A Warlock raid utility for WoW 1.12.1 that streamlines the summoning process with auto-detection of combat, instance mismatches, and coordinated summon lists.

## Requirements

- World of Warcraft 1.12.1 (Vanilla)
- **Strongly Recommended**: [SuperWoW client](https://github.com/balakethelock/SuperWoW) for enhanced functionality

## Features

- **Automated Summon List**: Detects "123" messages and builds a shared summon queue
- **Smart Detection**: Identifies combat status and instance mismatches
- **Coordination**: Syncs summon lists between warlocks to prevent duplicate summons
- **Class Prioritization**: Automatically sorts warlocks to the top of the list
- **Visual Clarity**: Uses class colors for easy identification

## Usage

1. Players type `123` in raid chat, say, or yell
2. Their name appears in the RaidSummonPlus frame (visible only to warlocks)
3. **Left-click** a name to summon and remove from list
4. **Ctrl+Left-click** to target a player without summoning
5. **Right-click** to remove without summoning
6. **Shift+Left-click** to move the frame

The addon window only appears when players need summons and automatically hides when empty.

## Commands

- `/rsp` or `/raidsummonplus` - Toggle the display
- `/rsp help` - Show all available commands
- `/rsp zone` - Toggle location info in messages
- `/rsp whisper` - Toggle whisper notifications to summoned players
- `/rsp shards` - Toggle display of shard count in announcements
- `/rsp debug` - Toggle detailed debug messages

Legacy commands (`/rs` and `/raidsummon`) also work for users transitioning from the original addon.

## Why SuperWoW Is Recommended

While RaidSummonPlus works with standard WoW 1.12.1 clients, SuperWoW provides substantial benefits:

| Feature | Standard Client | SuperWoW Client |
|---------|----------------|-----------------|
| Summon UI | ✓ | ✓ |
| Combat detection | ✓ (Basic) | ✓ (Enhanced reliability) |
| Instance detection | ✓ (Basic) | ✓ (Enhanced reliability) |
| Coordination between addon users | ✓ | ✓ |
| Detect summons from non-addon users | ✗ | ✓ |
| Detailed failure information | Limited | Comprehensive |

**SuperWoW automatically detects and prevents duplicate summons from any warlock in your raid** - even if they don't have RaidSummonPlus installed!

## Recent Updates

- Added SuperWoW integration
- Improved combat and instance mismatch detection
- Added persistent window positioning
- Fixed issues with addon communication
- Enhanced class color display

---

*RaidSummonPlus is an enhanced version of the original RaidSummon addon by Luise.*
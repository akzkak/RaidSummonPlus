# RaidSummonPlus

![RaidSummonPlus_screenshot](https://github.com/user-attachments/assets/2fb51929-e05b-44ac-9e40-ab2d49704c68)

A Warlock raid utility for WoW 1.12.1 that streamlines the summoning process with auto-detection of combat, instance mismatches, and coordinated summon lists.

## Features

- **Automated Summon List**: Detects "123" messages and builds a shared summon queue
- **Warlock Coordination**: Detect other warlocks' summons and syncs lists between users of the addon
- **Smart Detection**: Identifies combat status and instance mismatches
- **Healthstone Announcements**: Announces healing value of healthstones when casting Ritual of Souls based on Master Conjuror talent ranks
- **Soulstone Tracking**: Monitors active soulstones in your group with timers

## Warlock Coordination

1. **Basic Detection**: The addon attempts to monitor combat log messages to detect when any warlock begins summoning a player. This works with all warlocks but has limitations in accurately identifying summon targets.
2. **Enhanced Sync**: When multiple warlocks use RaidSummonPlus, their summon lists stay perfectly synchronized, providing seamless coordination.

## Usage

### Summon List
1. **Left-click** a name to summon and remove from list
2. **Ctrl+Left-click** to target a player without summoning
3. **Right-click** to remove without summoning

### Soulstone Tracking
1. **Left-click** on an active soulstone entry to target that player
2. **Left-click** on an expired soulstone to apply a new soulstone to that player
3. **Right-click** to remove the entry from the list

## Commands

- `/rsp` or `/raidsummonplus` - Toggle the display
- `/rsp help` - Show all available commands
- `/rsp zone` - Toggle location info in messages
- `/rsp whisper` - Toggle whisper notifications to summoned players
- `/rsp shards` - Toggle display of shard count in announcements
- `/rsp ritual` - Toggle Ritual of Souls announcements

## Recent Updates

- Added Soulstone tracking with timers
- Improved warlock coordination
- Enhanced UI with improved hover effects and class coloring
- Fixed frame layout and positioning
- Added Ritual of Souls announcements with Master Conjuror talent detection

---

*RaidSummonPlus is an enhanced version of the original RaidSummon addon by Luise.*
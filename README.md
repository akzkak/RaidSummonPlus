# RaidSummonPlus

![WoW_27-03-25](https://github.com/user-attachments/assets/581a47b7-1603-4118-83b1-7e17e7f0ac9d)

A Warlock raid utility for WoW 1.12.1 that streamlines the summoning process with auto-detection of combat, instance mismatches, and coordinated summon lists.

## Features

- **Automated Summon List**: Detects "123" messages and builds a shared summon queue
- **Smart Detection**: Identifies combat status and instance mismatches
- **Coordination**: Syncs summon lists between warlocks who have the addon
- **Class Prioritization**: Automatically sorts warlocks to the top of the list
- **Visual Clarity**: Uses class colors for easy identification

## Usage

1. Players type `123` in raid chat, say, or yell
2. Their name appears in the RaidSummonPlus frame
3. **Left-click** a name to summon and remove from list
4. **Ctrl+Left-click** to target a player without summoning
5. **Right-click** to remove without summoning

The addon window only appears when players need summons and automatically hides when empty.

## Commands

- `/rsp` or `/raidsummonplus` - Toggle the display
- `/rsp help` - Show all available commands
- `/rsp zone` - Toggle location info in messages
- `/rsp whisper` - Toggle whisper notifications to summoned players
- `/rsp shards` - Toggle display of shard count in announcements

## SuperWoW Enhancement (Optional)

While RaidSummonPlus works perfectly with standard WoW 1.12.1, it gains additional capabilities when used with [SuperWoW](https://github.com/balakethelock/SuperWoW):

**Key Benefit**: When multiple warlocks use RaidSummonPlus, their summon lists stay synchronized.
With SuperWoW, your list will stay synchronized with ALL warlocks in the raid, even those who don't have RaidSummonPlus installed.


### Easy SuperWoW Installation

1. Download [SuperWoW](https://github.com/balakethelock/SuperWoW) and the [VanillaFixes launcher](https://github.com/hannesmann/vanillafixes)
2. Place `SuperWoWhook.dll` in your game directory
3. Launch the game using the VanillaFixes launcher

The addon will automatically detect SuperWoW and enable the enhanced coordination.

## Recent Updates

- Added SuperWoW integration for cross-addon coordination
- Improved combat and instance mismatch detection
- Added persistent window positioning
- Fixed issues with addon communication

---

*RaidSummonPlus is an enhanced version of the original RaidSummon addon by Luise.*
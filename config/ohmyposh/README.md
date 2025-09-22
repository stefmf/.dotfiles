# Oh My Posh Responsive Configuration

## Overview
This responsive Oh My Posh configuration progressively simplifies as terminal width decreases, maintaining readability while preserving all original styling, colors, and icons.

## Implementation Summary

### Key Changes Made
1. **Added conditional templates** using `{{ if ge/lt (atoi .Env.COLUMNS) X }}` logic
2. **Introduced single-line compact mode** for Narrow-3 and Critical (≤69 cols)
3. **Added overflow handling** with `"overflow": "hide"` on right-aligned block
4. **Preserved all original styling** - no color, icon, or design changes

### Responsive Breakpoints & Rationale

| Width Range | Behavior | Rationale |
|-------------|----------|-----------|
| **≥100 cols (Wide)** | Show everything as original | Plenty of space for full prompt |
| **85-99 cols (Narrow-1)** | All left segments + conditional right time | Right block naturally hides via overflow when needed |
| **70-84 cols (Narrow-2)** | Session + path + git (no exec time) | Keep git, hide execution time and right time |
| **60-69 cols (Narrow-3)** | Single-line: `user@host <path> % ` | Compact fused prompt in macOS style |
| **≤59 cols (Critical)** | Single-line: `user@host <path> % ` | Minimal mode; `~` for home, collapsed path |

### Technical Implementation

#### Narrow-3 and Critical (≤69 cols)
- **Single text segment** outputs: `user@host <path> % ` (or `# ` if root)
- Path rules:
   - At home: `~`
   - In home subdirs: `~/parent/current` (last two segments)
   - Outside home: `…/parent/current` (last two segments), falling back to absolute path if too shallow
- Prompt char: `%` for non-root, `#` for root
- All other segments are hidden below 70 cols

#### Progressive Hiding
- **Path segment**: Hidden below 70 cols via conditional template
- **Git segment**: Hidden below 70 cols via conditional template  
- **Execution time**: Hidden below 85 cols via conditional template
- **Right time block**: Hidden below 85 cols + overflow protection

## Test Matrix

| Terminal Width | Session | Path | Git | Exec Time | Right Time | Final Output Example |
|----------------|---------|------|-----|-----------|------------|---------------------|
| **120 cols** | ` user ❘ 󰇄 host ❘` | ` ~/projects/dotfiles` | ` main* ↑` | ` ⏱ 123ms` | `Jan 2 15:04` | Full original prompt |
| **100 cols** | ` user ❘ 󰇄 host ❘` | ` ~/projects/dotfiles` | ` main* ↑` | ` ⏱ 123ms` | `Jan 2 15:04` | Full original prompt |
| **90 cols** | ` user ❘ 󰇄 host ❘` | ` ~/projects/dotfiles` | ` main* ↑` | ` ⏱ 123ms` | `Jan 2 15:04` | Full left + right time |
| **80 cols** | ` user ❘ 󰇄 host ❘` | ` ~/projects/dotfiles` | ` main* ↑` | Hidden | Hidden | Session + path + git |
| **70 cols** | ` user ❘ 󰇄 host ❘` | ` ~/projects/dotfiles` | ` main* ↑` | Hidden | Hidden | Session + path + git |
| **65 cols** | `user@host ~/projects/dotfiles % ` | Hidden | Hidden | Hidden | Hidden | Single-line compact |
| **60 cols** | `user@host ~/projects/dotfiles % ` | Hidden | Hidden | Hidden | Hidden | Single-line compact |
| **55 cols** | `user@host ~ % ` (if home) | Hidden | Hidden | Hidden | Hidden | Critical single-line |
| **45 cols** | `user@host ~/dotfiles % ` | Hidden | Hidden | Hidden | Hidden | Critical mode only |
| **35 cols** | `user@host ~/dotfiles % ` | Hidden | Hidden | Hidden | Hidden | Critical mode only |

## Documentation References

### Primary Sources Used
1. **[Oh My Posh Templates](https://ohmyposh.dev/docs/configuration/templates)**
   - Environment variables: `.Env.COLUMNS` for terminal width detection
   - Template logic: Conditional statements with `{{ if }}` and comparison functions
   - Global properties: `.UserName`, `.HostName`, `.PWD`, `.Root`, `.Folder`

2. **[Block Configuration](https://ohmyposh.dev/docs/configuration/block)**
   - `overflow: "hide"` for right-aligned blocks
   - Block alignment and segment organization

3. **[Segment Configuration](https://ohmyposh.dev/docs/configuration/segment)**
   - Conditional segment hiding via empty template returns
   - Segment template properties and styling preservation

4. **[Path Segment](https://ohmyposh.dev/docs/segments/system/path)**
   - Path properties and template variables
   - `max_width` dynamic sizing (preserved from original)

### Key Insights from Documentation
- **Template Logic**: Supports nested conditionals and comparison functions (`ge`, `lt`, etc.)
- **Environment Access**: `.Env.COLUMNS` provides reliable terminal width
- **Segment Hiding**: Empty template strings effectively hide segments including decorations
- **Overflow Handling**: Right blocks can gracefully hide when space is insufficient

## Usage Instructions

1. **Installation**: The responsive configuration is now active in your prompt.json
2. **Testing**: Resize your terminal to see progressive simplification
3. **Customization**: Adjust width thresholds in templates if needed
4. **Reverting**: Use `prompt_original.json` backup to restore original behavior

## Caveats & Limitations

1. **COLUMNS Variable**: Requires shell to properly set `$COLUMNS` environment variable
2. **Template Complexity**: More complex templates may have slight performance impact
3. **Font Dependencies**: Icons and separators still depend on font support
4. **Testing**: Actual behavior may vary slightly between terminals and shells

The implementation preserves 100% of your original styling while adding intelligent responsiveness that gracefully degrades as terminal width decreases.
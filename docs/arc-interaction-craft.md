# Arc interaction feedback

Scope checked against [Arthur Objartel's October 22, 2026 thread](https://x.com/arthur_objartel/status/2113386572561211881) and upstream main at `38befbb`. Open PRs were checked on October 23, 2026; they are proposals, not shipped features.

| Thread feedback | Existing implementation or proposal | Scope |
| --- | --- | --- |
| Easy space creation | Profile creation and shared browsing-data groups already exist; the pager switches between profiles | Companion profile-creation PR adds a visible footer + even with one profile, and icon choice during creation. Swipe past the last profile remains unchanged. |
| Recognizable space icons | [PR #25](https://github.com/mantrakp04/ardia/pull/25) adds configurable switcher icons | Defers to #25; keeps the existing dots |
| Refined active-tab shadows | Native `Surface` already supplies separate shadow layers and continuous plate corners | Preserves current styling; no claim of pixel parity with Arc |
| Navigation in the sidebar | Existing address-bar placement setting | No duplicate implementation |
| Smooth toolbar auto-hide | Existing `AutoHideToolbar` and reduced-motion handling | No change |
| Drag existing tabs into splits, including vertical and three-pane layouts | Store already supports horizontal, vertical and stacked layouts with up to three live tabs | Adds top/bottom page targets and a labeled Split target at the right of eligible sidebar rows; center drops still group tabs |
| Link Peek | [PR #12](https://github.com/mantrakp04/ardia/pull/12) implements the temporary link overlay | Defers to #12; sidebar hover-reveal is a separate feature |
| Rich theme editing | Existing movable gradient stops, textures, intensity, grain, blur and Light/Dark/System controls | Companion theme-preview PR corrects the miniature preview to follow the theme being edited |
| Tab press feedback | Existing hover/selection fills | Adds a small press-and-release scale animation to ordinary tab rows and split-pane buttons, disabled by Reduce Motion |
| Continuous corners | Existing native `Surface` plate uses continuous corners | No change |
| Folders | Existing collapsible groups; [#39](https://github.com/mantrakp04/ardia/pull/39) adds nesting and [#40](https://github.com/mantrakp04/ardia/pull/40) mixed pinned ordering | Defers to those proposals |

[PR #48](https://github.com/mantrakp04/ardia/pull/48) changes sidebar typography and row metrics, [#47](https://github.com/mantrakp04/ardia/pull/47) adds copy-link controls, and [#49](https://github.com/mantrakp04/ardia/pull/49) adds download previews. This change does not reimplement them. The switcher and sidebar drag changes may need a rebase when #25 or #48 lands.

## Verification

Focused tests exercise all four page edges, continuous target transitions, same-window/profile requirements, self/full-split rejection, third-pane insertion, stacked layouts, and preservation of existing tab IDs and live state. Existing session, privacy, tab, pin geometry and theme checks cover adjacent behavior.

Code validation passed: browser TypeScript, all 479 browser tests with file concurrency limited to one, and the Metro macOS JavaScript bundle on the combined companion changes. The user requested no native app builds or launches on this Mac. A prior guarded build attempt failed because generated Pods configuration and a signing profile were unavailable. Before merge, use another configured environment to exercise a hidden Debug instance with scratch `ARDIA_DATA_DIR`:

1. Create and cancel profiles from +, including one-profile and narrow-sidebar windows with Downloads visible; select a symbol or emoji and confirm it persists.
2. Drag a tab across all four page targets, then drop above/below an existing pane. Add a third tab and verify a fourth cannot join.
3. Drop on a sidebar row's Split target; drop on its center to create a group; reorder using its edges. Repeat with grouped and pinned tabs.
4. Check ordinary and split-pane press feedback, quick clicks, drag cancellation, and Reduce Motion. Verify shadows remain visible at list and folder boundaries.
5. Edit a theme's Light/Dark/System setting while the settings window has a different appearance; verify its miniature preview follows the edited theme.

No installed app, user browser profile, release or engine source was changed.

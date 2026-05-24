# r277.7.3 Dispel Filters, Shaman Poison & Taint Fixes

- Fixed false-positive dispel indicators displaying non-dispellable debuffs (e.g. Diseases on Priests) when "Only show debuffs dispellable by me" is enabled, by restoring the Blizzard API filter as the primary source of truth.
- Isolated Shaman Poison dispel: Poisons remain correctly recognized as dispellable using internal fallbacks, bypassing Blizzard API filtration limitations.
- Restored proper user filter ('Only show debuffs dispellable by me') enforcement on secret/private auras within the debuff handling pipeline.
- Fixed taint-related LUA errors (attempt to compare secret values in PartyMemberFrame, TextStatusBar, and UnitFrame) when Blizzard imperatively updates hidden party and pet frames while the execution thread is tainted by Cell.
- The “Left” gradient option has been added to the Private Dispel Overlay, and the bug that prevented the “Bottom” gradient from appearing has been fixed.


# r277.7.2 Private Dispel & NameText Fixes

- Fixed the Blizzard Private Dispel Overlay incorrectly appearing on secret normal dispellable debuffs (e.g. Raid Debuffs) instead of Cell's native dispel indicators.
- Fixed a LUA error (attempt to perform string conversion on a secret string value) in name/vehicle text SetPoint positioning by strictly catching secret string conversions in `IsValueNonSecret`.

# r277.7-krysio Private Dispel & Overlay Fixes

- Fixed a LUA error (bad self) when calling 'IsShown' on restricted private aura anchors during unit frame updates.
- Added priority filtering: Blizzard's Private Dispel Overlay is now automatically hidden if any normal (non-secret) dispellable debuffs are active, allowing Cell's own custom debuff/dispel indicators to take absolute priority.
- Optimized SetAlpha updates to prevent Blizzard's secure PrivateAuraContainer from getting stuck in combat.

# r277.6.2-krysio Private Dispel Overlay Fix

- Fixed Blizzard dispel overlay displaying on standard (non-private) dispellable debuffs when the Private Dispel Overlay option is enabled.

# r277.6.1-krysio Arena LGI Compatibility Fix

- Fixed a LUA error in LibGroupInfo when entering arena matches or high-restriction combat environments where UnitGUID returns secret keys.

# r277.6-krysio Private Dispel Overlay & targetedSpells disabled

- Added a new Private Dispel Overlay option for customizable group/raid frame overlays on dispellable private auras.
- Added customization settings: Overlay Alpha, Overlay Frame Level, and Overlay Inset.
- Disabled Targeted Spells internally due to Blizzard API restrictions causing unstable behavior and LUA errors on modern clients.

# r277.5-krysio Private Aura frame level/z-order stabilization

- Fixed intermittent private aura z-order issues where icons could render behind unit frames.
- Added explicit private aura anchor strata/frame-level enforcement on anchor refresh.
- Stabilized per-slot ordering with deterministic index-based frame levels.
# r277.3-krysio Missing Buffs / Raid Debuffs / TexCoord hotfix

- Fixed false-positive Missing Buffs persistence for Blessing of the Bronze and improved class buff alias handling.
- Added combat hide/suspend behavior for Bronze buff tracking with resync on combat transitions.
- Fixed normal debuffs occasionally appearing in Raid Debuffs position during encounters.
- Fixed TexCoord out-of-range errors when indicator icon size is zero/invalid.
# r275.8-skyking-dev Compatibility reports, diagnostics, and curation tools

## Compatibility & Stability
- Added a compatibility report that persists "No" on old-profile reset prompts and points to the affected layouts/indicators instead of asking again every login.
- Indicators now surface compatibility issues directly in the list, with red highlighting and tooltips for invalid spell IDs, duplicate built-ins, and missing built-ins.
- Fixed `secret boolean` crashes in range and group checks by guarding `UnitIsUnit`, `UnitInParty`, `UnitInRaid`, and related target-resolution helpers.

## Tools & Backups
- Added an About notifications center plus automatic snapshots around imports and destructive flows, with reuse/retention controls for auto backups.
- Added Midnight diagnostics and utility tools for comm restrictions, queued sync traffic, and group version visibility.

## Raid Debuffs
- Added raid debuff curation metadata, reporting, and review states to make Midnight debuff cleanup easier without losing the underlying spell list.

# r275.6 Midnight dispel filtering and private aura options

## Indicators
- Dispels now use Midnight's per-aura server-side dispel filter so raid frames only flag debuffs you can actually remove on that specific unit.
- Secret dispellable auras now feed the same decision path as visible dispels, improving self-only and restricted dispel handling.
- Private Auras can now anchor and display more than one Blizzard private aura at a time.
- Added a new Private Aura option to control the maximum number of displayed private aura anchors while preserving Blizzard styling restrictions.

# r275.5 Added Midnight Raid Debuffs

## Raid Debuffs
- Added initial Midnight expansion raid debuffs for all 12 instances (6 raids, 6 dungeons) and 41 bosses.
- Boss ability spell IDs sourced from the Encounter Journal via wago.tools DB2 tables.
- General (trash mob) debuffs still need to be collected in-game and added in a future update.
- Spells may need further in-game curation to filter out non-debuff abilities.

# r275-release â€” WoW 12.0.0 (Midnight) Compatibility

Comprehensive compatibility update for WoW Patch 12.0.0 (Midnight), addressing the removal of `COMBAT_LOG_EVENT_UNFILTERED`, the introduction of Secret Values, blocked addon communications during restricted contexts, and spell/API removals. Interface bumped to 120001.

## Secret Values (12.0.0+)
- Add `Cell.isMidnight` detection flag and `F.IsSecretValue()`, `F.IsAuraRestricted()`, `F.IsCooldownRestricted()` utility functions
- Add per-aura `F.IsAuraNonSecret()`, `F.IsSpellAuraNonSecret()`, `F.IsValueNonSecret()` helpers â€” non-secret (whitelisted) auras now get real countdown timers, source detection, and duration display; secret auras gracefully degrade
- UnitButton: major dual-path refactor â€” Midnight uses `UnitHealPredictionCalculator`, `C_CurveUtil.CreateCurve()`, and StatusBar overlays for health/prediction/shields; pre-Midnight retains arithmetic-based paths
- Appearance: IncomingHeal widget uses `SetStatusBarTexture` on Midnight (StatusBar) vs `SetTexture` pre-Midnight (Texture)
- Indicator_Defaults: local `DebuffTypeColor` fallback for when the WoW global is removed
- Per-field `F.IsValueNonSecret()` guards before every arithmetic operation on temporal aura fields (`expirationTime`, `duration`, `applications`, and cached `old*` variants)

## CLEU Removal
- AoEHealing: disabled on Midnight (CLEU unavailable); frame still exists for potential future non-CLEU API
- StatusIcon: soulstone/resurrection tracking switches to `UNIT_AURA` + `UNIT_HEALTH` on Midnight
- NPCFrame: boss6-8 health/aura tracking switches to unit events on Midnight
- DeathReport: full refactor â€” Midnight uses `UNIT_HEALTH` + `UnitIsDeadOrGhost()` for death detection
- UnitButton: removed `CombatLogGetCurrentEventInfo` dependency and `CheckCLEURequired`
- General: removed `useCleuHealthUpdater` checkbox (CLEU health updater obsolete)
- Revise: r275 migration removes `useCleuHealthUpdater` from saved variables

## Comm Restrictions
- Comm: `IsCommRestricted()` detects encounters/M+/PvP; all `SendCommMessage` calls guarded; pending queue with flush on `ENCOUNTER_END`
- Nicknames: all nickname sync sends guarded with `F.IsCommRestricted()`

## Heal Prediction & Health Bar Fixes
- Created a dedicated `healPredictionCalculator` separate from the shared `healthCalculator` â€” the heal prediction function's `SetIncomingHealClampMode(0)` and `SetIncomingHealOverflowPercent(1.0)` were persisting on the shared calculator and corrupting health/absorb reads
- Incoming heal bar is now a StatusBar (instead of Texture) anchored to the health fill texture edge
- Fixed health bar loss color stuck on white/full-health â€” `self.states.healthPercent` was never set on the Midnight path; now populated from `calculator:GetCurrentHealthPercent()` with a secret-safe fallback
- Dispels now show correctly because `HandleDebuff` completes to the dispel detection code (string/boolean fields, not temporal arithmetic)

## Spell & Default Updates
- Removed: Engulf, Renew, Power Word: Life, Void Shift, Shadow Covenant, Divine Star, Cloudburst Totem, Minor Cenarion Ward, Premonition of Solace
- Added: Plea (200829, Disc Priest)
- Added missing healing spells to default indicator list (Evoker, Monk, Paladin, Priest)
- Moved: Prayer of Mending from class-wide to Holy spec only
- Fixed: Shaman Poison dispel node IDs (103609 â†’ 103599)

## Defensive Nil Guards & Fixes
- MainFrame: nil guards for `currentLayoutTable` and `tooltipPoint`
- HideBlizzard: guards for `PartyMemberFramePool`, `CompactPartyFrame`, `PartyMemberBackground`
- RaidDebuffs: nil guard for encounter journal expansion data
- TargetedSpells: skip enemy spell tracking during restricted periods
- BuffTracker: guard `GetAuraDataBySpellName` when auras are restricted; per-aura `sourceUnit` check
- QuickCast: skip only secret auras in `ForEachAura`
- Custom indicators: per-aura secret check for duration/start
- Appearance: ticker nil guard in preview `OnHide`

## Infrastructure
- All 22 XML files updated from `FrameXML/UI_shared.xsd` â†’ `Blizzard_SharedXML/UI.xsd`
- Core: version constants bumped to 275, `GetBattlegroundInfo` guard added

---

# r274-release

[View Full Changelog](https://github.com/enderneko/Cell/compare/r273-release...c376c32494926a90b93cc63bfc564234fb6e5cd6)

- Update Molten Core debuffs
- Fix boss unit button mapping



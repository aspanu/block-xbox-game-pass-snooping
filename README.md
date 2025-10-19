# Xbox Privacy – Keep Game Pass, Stop Game Snooping

## block-xbox-game-pass-snooping
A PowerShell utility that lets you **keep Xbox Game Pass fully functional** while **blocking Windows and the Xbox app from auto-detecting every game installed on your PC**.

---

## 🎯 What It Does

- Prevents Windows “Game Detection” and Xbox Game Bar services from scanning all drives.
- Disables registry flags and scheduled tasks that auto-add Steam/Epic/GOG titles.
- Keeps Game Pass downloads, cloud saves, and achievements fully working.
- (Optional) **DeepClean** mode disables Xbox Live background services and telemetry so “last played” no longer updates for non-Game Pass games.
- (Optional) Clears cached lists of previously detected non-Store games.
- Fully reversible — run with `-Undo` to restore defaults.

---

## ⚙️ Usage

1. **Download** `xbox-privacy-keep-gamepass.ps1`.
2. **Open PowerShell as Administrator** in the script’s folder.
3. Choose one of these:

```powershell
# Basic privacy mode (stop drive scanning only)
powershell -NoProfile -ExecutionPolicy Bypass -File .\xbox-privacy-keep-gamepass.ps1

# DeepClean mode (also disable Xbox Live presence & telemetry)
powershell -NoProfile -ExecutionPolicy Bypass -File .\xbox-privacy-keep-gamepass.ps1 -DeepClean

# DeepClean + clear cached external games
powershell -NoProfile -ExecutionPolicy Bypass -File .\xbox-privacy-keep-gamepass.ps1 -DeepClean -ClearExternalGameCache

# Restore all defaults
powershell -NoProfile -ExecutionPolicy Bypass -File .\xbox-privacy-keep-gamepass.ps1 -Undo
```

Please send any PRs for any other issues. Thanks!

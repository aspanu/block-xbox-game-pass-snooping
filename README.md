# Xbox Privacy – Keep Game Pass, Stop Game Snooping

## block-xbox-game-pass-snooping
A PowerShell utility that lets you **keep Xbox Game Pass fully functional** while **blocking Windows and the Xbox app from auto-detecting every game installed on your PC**.

---

## 🎯 What It Does

- Prevents Windows “Game Detection” and Xbox Game Bar services from scanning all drives for `.exe` files.
- Disables scheduled tasks and registry flags that make the Xbox app list your Steam / Epic / GOG games.
- Keeps `Gaming Services` active so **Game Pass games, cloud saves, and achievements** continue to work.
- Optional: clears the Xbox app’s cached list of previously detected non-Store games.
- Fully reversible — run with `-Undo` to restore defaults.

---

## ⚙️ Usage

1. **Download** `xbox-privacy-keep-gamepass.ps1`.
2. **Open PowerShell as Administrator.**
3. Run one of the following:

```powershell
# Apply privacy tweaks
.\xbox-privacy-keep-gamepass.ps1

# Undo and restore defaults
.\xbox-privacy-keep-gamepass.ps1 -Undo

# Apply and also clear Xbox app external-game cache
.\xbox-privacy-keep-gamepass.ps1 -ClearExternalGameCache
```

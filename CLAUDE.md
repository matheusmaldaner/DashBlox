# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Zombie Survival** is a wave-based zombie shooter Roblox game where players:
1. Spawn into an arena/map with a starter weapon
2. Fight waves of zombies that get progressively harder
3. Earn coins from killing zombies (more coins for tougher zombies)
4. Spend coins in the shop to buy better guns, ammo, perks, and barricades
5. Survive as long as possible, with rebirth/prestige for permanent boosts

The game is **strictly server-authoritative** for all logic (damage, health, inventory, economy, wave management). Clients handle input, aiming, and visuals.

NO FILE SHOULD BE BIGGER THAN 500 LINES, MOVE TO DIFFERENT FUNCTION IF HAVE TO AND CALL IT

## Development Commands

### Build & Sync
```bash
rojo build default.project.json -o build.rbxl  # Build place file
rojo serve default.project.json                # Live sync to Studio
```

### Linting
```bash
selene src/  # Lint Luau code (uses selene.toml config)
```

### Tools
Managed via Aftman (see `aftman.toml`):
- Rojo 7.6.1 for project sync

## Architecture

### Directory Structure
```
src/
├── ReplicatedStorage/          # Shared modules & remotes
│   ├── Modules/               # Shared logic
│   │   ├── GunConfig.lua      # Weapon stats, fire rates, damage, ammo
│   │   ├── ZombieConfig.lua   # Zombie types, health, speed, rewards
│   │   ├── WaveConfig.lua     # Wave definitions (zombie counts, types per wave)
│   │   ├── ShopConfig.lua     # Shop items, prices, unlock requirements
│   │   ├── GridSnap.lua       # Grid placement utilities (barricades)
│   │   ├── CameraFollow.lua   # Camera system
│   │   ├── NumberFormatter.lua # Number display utilities
│   │   └── TutorialArrow.lua  # Tutorial system
│   ├── RemoteService.lua      # Centralized remote registry
│   ├── ProfileStore.lua       # Data persistence module (external)
│   ├── UIManager.lua          # UI utilities
│   └── ZoneBuilder.lua        # Zone construction
│
├── ServerScriptService/        # Server-only code
│   └── Services/              # Server services (*.server.lua or .lua)
│       ├── DataService.lua           # ProfileStore integration
│       ├── PlayerData.lua            # Player state management
│       ├── WaveService.lua           # Wave spawning & progression
│       ├── ZombieService.lua         # Zombie AI, pathfinding, health
│       ├── GunService.lua            # Weapon handling, hit validation, ammo
│       ├── ShopService.lua           # In-game shop (buy guns, perks, ammo)
│       ├── DamageService.lua         # Server-side damage calculation
│       ├── BarricadeService.lua      # Barricade placement & health
│       ├── PlotService.lua           # Plot/lobby assignment
│       ├── GamePassService.lua       # GamePass handling
│       ├── RebirthService.lua        # Rebirth/prestige system
│       ├── PlaytimeRewardsService.server.lua  # Playtime rewards
│       ├── DailyTasksService.lua     # Daily task system
│       ├── LoginBonusService.server.lua      # Login streak rewards
│       ├── AchievementService.lua    # Achievement tracking
│       ├── LeaderboardService.lua    # Leaderboard system
│       ├── CodeService.server.lua    # Promo code redemption
│       ├── VerifyService.server.lua  # Social verification (X/Twitter)
│       ├── GroupRewardService.server.lua  # Group membership rewards
│       ├── FriendBoostService.lua    # Friend count boosts
│       ├── GiftingService.lua        # Gift system
│       ├── DevProductService.lua     # Robux purchase handling
│       └── AnalyticsService.lua      # Funnel tracking
│
└── StarterPlayer/StarterPlayerScripts/  # Client-only code
    ├── Combat/                # Combat-related client scripts
    │   ├── GunController.client.lua       # Shooting, aiming, reloading visuals
    │   ├── CrosshairController.client.lua # Crosshair/reticle rendering
    │   └── HitMarkerController.client.lua # Hit feedback effects
    ├── Zombies/               # Zombie client visuals
    │   └── ZombieEffects.client.lua       # Death anims, damage numbers
    └── UI/                    # UI controllers
        ├── ShopController.client.lua          # Weapon/perk shop UI
        ├── WaveHudController.client.lua       # Wave counter, zombie count
        ├── AmmoHudController.client.lua       # Ammo display
        ├── HealthHudController.client.lua     # Player health bar
        ├── GamePassShopController.client.lua
        ├── RebirthController.client.lua
        ├── PlaytimeRewardsController.client.lua
        ├── DailyTasksController.client.lua
        ├── LoginBonusController.client.lua
        ├── AchievementController.client.lua
        ├── LeaderboardController.client.lua
        ├── SettingsController.client.lua
        ├── NotificationController.client.lua
        ├── CoinsDisplayController.client.lua
        ├── CurrencyDisplayController.client.lua
        └── PlotController.client.lua
```

### Key Systems

#### 1. Data Persistence (ProfileStore)
- **DataService.lua**: ProfileStore wrapper, session locking, auto-save
- **PlayerData.lua**: Player state API (coins, gems, XP, playtime, rebirth)
- **Profile Template**:
  - `Coins`, `Gems`, `XP`: Currency/progression
  - `RebirthLevel`: Prestige level
  - `Playtime`: Total play time
  - `OwnedGuns`: Table of unlocked weapons
  - `OwnedPerks`: Table of unlocked perks
  - `HighestWave`: Best wave reached (for leaderboards)
  - `TotalKills`: Lifetime zombie kills
  - `EquippedLoadout`: Currently selected weapons
- **CRITICAL**: Install ProfileStore at `ReplicatedStorage/ProfileStore`

#### 2. Networking (RemoteService)
- **RemoteService.lua**: Centralized remote registry
- All remotes declared in `remoteRegistry` with types (RemoteEvent/RemoteFunction)
- Built-in rate limiting via `CreateRateLimiter(cooldown)`
- **Key Remote Categories**:
  - Player Data: `GetPlayerData`, `SetCameraMode`, `SetUserSetting`
  - Combat: `FireGun`, `ReloadGun`, `HitRegistration`, `ZombieDied`, `PlayerDamaged`
  - Waves: `WaveStarted`, `WaveCompleted`, `WaveCountdown`
  - Shop: `BuyGun`, `BuyAmmo`, `BuyPerk`, `BuyBarricade`, `GetShopData`
  - Loadout: `EquipGun`, `SwapWeapon`, `GetOwnedGuns`
  - Rebirth: `OpenRebirthUI`, `PerformRebirth`, `RebirthCompleted`
  - GamePass: `GetGamePassStatus`, `PromptGamePassPurchase`, `GamePassStatusChanged`
  - Rewards: `ClaimPlaytimeReward`, `ClaimDailyTaskReward`, `ClaimLoginBonus`
  - Social: `ClaimGroupReward`, `ClaimXVerify`, `RedeemCode`

#### 3. Combat System
- **GunService** (server): Validates shots, calculates damage, manages ammo server-side
- **DamageService** (server): Applies damage to zombies, handles kill rewards
- **GunController** (client): Handles input (click to shoot, R to reload), plays animations, sends fire events
- **Hit validation**: Client sends ray origin + direction, server re-casts to verify hits
- **Damage falloff**: Optional distance-based damage reduction per weapon

#### 4. Zombie System
- **ZombieService** (server): Spawns zombies, runs AI, manages zombie health pools
- **ZombieConfig** (shared): Defines zombie types with stats (health, speed, damage, coin reward)
- **Zombie Types**: Normal, Fast, Tank, Exploder, Boss (per-wave scaling)
- **AI**: Pathfinding toward nearest player, attack on proximity
- **Pooling**: Reuse zombie models to reduce instance creation overhead

#### 5. Wave System
- **WaveService** (server): Controls wave progression, rest periods, difficulty scaling
- **Wave flow**: Rest period (buy phase) → Wave countdown → Zombies spawn → Kill all → Reward → Next wave
- **Scaling**: Each wave increases zombie count, health, speed; introduces new types at milestones
- **Between-wave shop**: Players can buy/upgrade during rest periods

#### 6. Shop & Economy
- **ShopService** (server): Handles purchases, validates player has enough coins
- **ShopConfig** (shared): Defines all purchasable items and prices
- **Categories**: Guns, Ammo Refills, Perks (speed boost, double damage, etc.), Barricades
- **Guns unlock permanently** (persist across sessions), ammo/perks are per-round

#### 7. Monetization Framework
- **GamePassService**: GamePass detection and effects (2x coins, starter pack, exclusive guns)
- **DevProductService**: Robux purchase handling (coin bundles, revives)
- **GiftingService**: Gift system for gamepasses/crates
- **RotatingCrateService**: Rotating loot crate system (weapon skins, effects)
- **GemCrateService**: Gem-purchased crates

#### 8. Progression Framework
- **RebirthService**: Prestige/rebirth system with permanent boost multipliers (coin multiplier, damage boost, starting wave skip)
- **PlaytimeRewardsService**: Tiered rewards for playtime
- **DailyTasksService**: Daily task completion for rewards (kill X zombies, reach wave Y, buy a gun)
- **LoginBonusService**: Streak-based daily login rewards
- **AchievementService**: Achievement milestones (total kills, waves survived, guns owned)

## Core Engineering Principles

### Server Authority
- **All** gameplay logic (damage, health, inventory, economy, waves) runs server-side
- Clients are **display-only**: render visuals, handle input, show UI
- Never trust client values (damage numbers, kill counts, currency, positions)
- **Hit validation**: Server re-verifies all shots; client only sends intent

### Networking Discipline
- All remotes in `RemoteService` with documented payloads
- Input validation and rate limiting on server
- Per-player remotes where appropriate
- Fire rate enforcement server-side (prevent rapid-fire exploits)

### Performance
- Avoid per-frame allocations (reuse tables, CFrames)
- Pool zombie models and bullet effects
- Use CollectionService tags over polling/loops
- Limit active zombie count; queue spawns if needed
- LOD for distant zombies (reduce animation complexity)

### Data Integrity
- All currency/progression managed through PlayerData API
- Data changes go through DataService for persistence
- Gun ownership and loadout validated server-side

### Lifecycle & Cleanup
- Every connection must be disconnectable
- Services expose Destroy methods
- Clean up on player leave, zombie death, round end
- Despawn zombie models back to pool on death

### Security
- Validate all client inputs against server state
- Rate limit remotes where needed (especially FireGun)
- Sanitize user input (text, numbers, vectors)
- Anti-cheat: server tracks fire rate, ammo count, and position reasonability
- Reject impossible shots (through walls, beyond weapon range)

## Game Flow

1. **Lobby/Spawn**: Player joins → spawns in lobby → matchmaking or solo start
2. **Wave Start**: Countdown timer → zombies begin spawning from spawn points
3. **Combat Phase**: Players shoot zombies → earn coins per kill → survive the wave
4. **Wave Clear**: All zombies dead → rest period begins → shop opens
5. **Shop Phase**: Players spend coins on guns, ammo, perks, barricades
6. **Next Wave**: Harder wave begins with more/tougher zombies
7. **Death**: Player dies → option to revive (Robux/gem) or spectate
8. **Game Over**: All players dead → results screen → coins earned summary
9. **Progression**: Permanent unlocks persist, rebirth for multiplier boosts

## Important Files

- **RemoteService.lua**: Add new remotes here
- **PlayerData.lua**: Player state API (coins, gems, rebirth, guns, kills)
- **DataService.lua**: Data persistence layer
- **GunConfig.lua**: All weapon definitions (damage, fire rate, ammo, cost)
- **ZombieConfig.lua**: All zombie type definitions (health, speed, reward)
- **WaveConfig.lua**: Wave progression definitions
- **default.project.json**: Rojo project structure

## Development Guidelines

### When Adding Features
1. Check if it's server logic → add to Services/
2. Check if it's client display → add to StarterPlayerScripts/
3. Check if it's shared → add to ReplicatedStorage/Modules/
4. Always add remotes to RemoteService registry first

### When Adding Weapons
1. Add weapon stats to `GunConfig.lua` (damage, fire rate, mag size, reload time, cost)
2. Add purchase logic in `ShopService.lua`
3. Add server-side fire handling in `GunService.lua`
4. Add client visuals/animations in `GunController.client.lua`
5. Add to shop UI in `ShopController.client.lua`

### When Adding Zombie Types
1. Add zombie stats to `ZombieConfig.lua` (health, speed, damage, coin reward)
2. Add spawning logic in `ZombieService.lua`
3. Add to wave definitions in `WaveConfig.lua`
4. Add client-side effects in `ZombieEffects.client.lua`

### When Adding Remotes
1. Add to `remoteRegistry` in RemoteService.lua
2. Document payload shape in comments
3. Add rate limiting if user-triggered
4. Validate inputs server-side

### When Working with Data
- Never modify profile data directly
- Use PlayerData API methods (AddCoins, AddGems, SpendCoins, etc.)
- All data changes must go through DataService for persistence

## TODO: Game-Specific Features to Implement

1. **Gun Registry**: Define all weapon types with full stats in GunConfig
2. **Zombie Registry**: Define all zombie types with stats in ZombieConfig
3. **Wave System**: Wave progression, scaling, spawn point management
4. **Combat System**: Shooting, hit detection, damage, ammo management
5. **Zombie AI**: Pathfinding, attacking, special abilities (explode, charge)
6. **Shop System**: Between-wave shop for guns, ammo, perks
7. **Death/Revive**: Player death handling, revive mechanic
8. **Barricade System**: Placeable defenses that zombies must break through
9. **Perk System**: Temporary per-round buffs (speed, damage, health regen)
10. **Weapon Skins**: Cosmetic system for gun skins via crates

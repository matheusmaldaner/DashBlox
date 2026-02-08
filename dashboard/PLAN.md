# DashBlox

**Project**: Web dashboard to accelerate Roblox game development with AI-powered 3D modeling, audio generation, project doc management, and kanban task tracking
**Duration**: Hackathon sprint (1-2 weeks) + ongoing side project
**Team Size**: 3 members (@matheusmaldaner, @adv-andrew, @luanamaldaner)

> **Current Status**: See [PROGRESS.md](./PROGRESS.md) for live tracking.

---

# Project Overview

## The Problem
1. Roblox game development requires constant context switching between tools: 3D modeling software, audio editors, project docs, task boards, and Roblox Studio
2. AI-powered asset generation (3D models, sound effects, voice lines) requires manually juggling multiple API dashboards, downloading files, converting formats, and uploading to Roblox
3. Project documentation (PLAN.md, PROGRESS.md) lives in raw markdown files with no structured viewer or quick-edit workflow
4. Task management for game dev teams relies on external tools (Trello, Notion) that have no integration with the actual game project

## The Solution
A unified web dashboard with four core tabs that brings everything into one place:
- **Models Tab**: AI 3D model generation with a multi-provider toggle (Meshy, Tripo, Rodin, Roblox Cube) powered by OpenRouter for prompt engineering. Generate, preview, and export game-ready assets
- **Audio Tab**: ElevenLabs-powered SFX and voice generation (evolved from fortnite-collab SFX generator). Create sound effects, NPC dialogue, and ambient audio
- **Project Docs Tab**: Structured viewer/editor for PLAN.md, PROGRESS.md files with markdown rendering, section navigation, and quick editing
- **Trello Board Tab**: Kanban-style task manager with drag-and-drop columns (To Do, In Progress, Done) persisted to MongoDB

Built with the NexHacks liquid glass design system, deployed on Vultr, backed by MongoDB Atlas, with an optional Solana-powered asset marketplace for trading generated assets.

**Hackathon Framing**: "An AI-powered Roblox game development dashboard that we used to build a Zombies game in record time." The dashboard IS the hackathon project. The Zombies game (`Roblox/Zombies/`) is the PROOF it works. Judges see both the tool AND the output.

**Sponsor Coverage**:
- Gemini API (via OpenRouter) - AI backbone for prompt enhancement, code generation, game design assistance
- ElevenLabs - SFX generation (zombie groans, weapon sounds, ambient horror), NPC voice lines, dynamic announcer ("Wave 5 incoming!"), voice modulation per zombie type
- MongoDB Atlas - All data persistence: dashboard state, asset metadata, Trello board, player stats, leaderboards
- Vultr - Host dashboard backend, API gateway, potential GPU instances for AI inference
- Solana (optional) - In-game token economy (earn per zombie kill, spend on upgrades), on-chain leaderboard verification, NFT weapon skins/achievement badges

---

# Core Features

## 1. Models Tab (AI 3D Generation)

Multi-provider AI 3D model generation with a unified interface.

**Provider Toggle**: Switch between providers via a dropdown/toggle at the top of the tab:
- **Meshy** (free trial / Pro tier) - Text-to-3D and Image-to-3D via REST API
- **Tripo3D** (free tier: 300 credits) - Best quad topology for games
- **Rodin/Hyper3D** (pay-per-use) - Highest fidelity generation
- **Roblox Cube** (free beta) - Native Roblox integration, limited to ~10k tris

**Workflow**:
1. User enters a text prompt or uploads a reference image
2. OpenRouter LLM refines the prompt into an optimized 3D generation prompt (provider-specific formatting)
3. Dashboard calls the selected 3D API
4. Progress polling shows generation status (Waiting/Generating/Ready)
5. 3D model preview rendered in-browser (three.js GLB/FBX viewer)
6. Download as FBX/GLB or direct upload to Roblox via Open Cloud Assets API
7. Asset metadata saved to MongoDB (prompt, provider, format, polycount, Roblox asset ID)

**Prompt Enhancement Pipeline**:
```
User prompt: "a medieval chair"
       |
       v
Gemini (via OpenRouter) -->
  "a sturdy wooden medieval tavern chair with carved armrests,
   aged oak finish, iron nail details, low-poly game asset style,
   clean topology suitable for Roblox"
       |
       v
Selected 3D API generates model
```

**3D Preview**: Embedded three.js canvas with orbit controls, grid floor, and basic lighting. Supports GLB and FBX preview before export.

## 2. Audio Tab (SFX and Voice Generation)

Evolved from the fortnite-collab `tools/sfx-generator/` with expanded capabilities.

**Sound Effects Generator**:
- Text prompt input for describing sound effects
- Duration slider (0.5s - 30s or auto)
- Prompt influence slider (creativity vs accuracy)
- Generate 10 parallel variations with staggered requests (600ms delay)
- Audio preview with play/pause controls per variation
- Download as MP3 with custom filename
- Upload to Roblox via Open Cloud Assets API

**Voice Generator (NPC Dialogue)**:
- Text input for dialogue lines
- Voice selection from ElevenLabs library (10,000+ voices) or custom clones
- Model selection (multilingual v2, turbo v2.5)
- Batch generation for multiple dialogue lines
- Preview and download
- Inline audio tags support: `[whispers]...[/whispers]`, `[pause:1s]`

**Voice Cloning**:
- Upload audio sample (30+ seconds)
- Create named character voice
- Assign cloned voice to all subsequent generations for that character

**All audio assets saved to MongoDB with metadata**: prompt, voice, duration, ElevenLabs model, cost, Roblox asset ID.

## 3. Project Docs Tab (Markdown Viewer/Editor)

Structured viewer for project markdown files with file system access.

**File Selector**: Dropdown to choose which project file to view:
- PLAN.md (project roadmap)
- PROGRESS.md (live tracking)

**Markdown Renderer**:
- Full CommonMark rendering with syntax highlighting for code blocks
- Table of contents sidebar generated from headings
- Section-level navigation (click heading to scroll)
- Checkbox interaction (toggle `- [ ]` to `- [x]` inline)

**Quick Edit Mode**:
- Toggle between rendered view and raw markdown editor
- Split-pane option (editor left, preview right)
- Save changes back to filesystem
- Auto-refresh on external file changes

**Project Switcher**: If multiple projects exist (fortnite-collab, Zombies, FortBox), switch between them to view their respective docs.

## 4. Trello Board Tab (Kanban Task Manager)

Drag-and-drop kanban board for game development task tracking.

**Columns**: To Do, In Progress, Review, Done (customizable)

**Cards**:
- Title, description, priority (low/medium/high/critical)
- Assignee (team member)
- Labels/tags (building, audio, UI, bug, feature)
- Due date
- Linked assets (reference a generated 3D model or audio clip by MongoDB ID)

**Interactions**:
- Drag cards between columns
- Click to expand card detail modal
- Create new cards with a quick-add input at the top of each column
- Edit/delete cards
- Filter by label, assignee, or priority

**Persistence**: All board state stored in MongoDB. Real-time sync via Change Streams so multiple team members see updates instantly.

---

# Technical Architecture

```
+---------------------------------------------------+
|                  BROWSER (Client)                  |
|                                                    |
|  +----------+ +--------+ +--------+ +-----------+ |
|  |  Models  | | Audio  | | Docs   | |  Trello   | |
|  |   Tab    | |  Tab   | |  Tab   | |   Board   | |
|  +----+-----+ +---+----+ +---+----+ +-----+-----+ |
|       |            |          |             |       |
|  three.js     Web Audio   Markdown      Drag&Drop  |
|  viewer       playback    renderer      (Sortable) |
+-------+------------+---------+-------------+-------+
        |            |          |             |
        v            v          v             v
+---------------------------------------------------+
|              Node.js Express Backend               |
|                                                    |
|  /api/models/*    /api/audio/*   /api/docs/*       |
|  /api/board/*     /api/assets/*  /api/auth/*       |
|                                                    |
|  Middleware: CORS, rate limiting, API key mgmt     |
+---+--------+--------+--------+--------+----------+
    |        |        |        |        |
    v        v        v        v        v
+------+ +------+ +-------+ +------+ +--------+
|OpenR.| |Eleven| |3D APIs| |Roblox| |Solana  |
|outer | |Labs  | |Meshy  | |Open  | |RPC +   |
|API   | |API   | |Tripo  | |Cloud | |Metaplex|
|      | |      | |Rodin  | |Assets| |        |
+------+ +------+ +-------+ +------+ +--------+
                                |
                         +------+------+
                         |   MongoDB   |
                         |   Atlas     |
                         |             |
                         | Collections:|
                         | - projects  |
                         | - assets_3d |
                         | - assets_au |
                         | - board     |
                         | - users     |
                         +-------------+
```

**Deployment on Vultr**:
```
Vultr Cloud Compute (vc2-2c-4gb, ~$24/mo)
  |
  +-- Docker Compose
       |
       +-- dashboard-frontend (nginx serving static HTML/CSS/JS)
       +-- dashboard-api (Node.js Express, port 3000)
       +-- mongo-express (optional admin UI, port 8081)
       |
       +-- Connected to MongoDB Atlas (external)
       +-- Connected to Solana RPC (external)
```

---

# Implementation Phases

## Phase 0: Project Setup
- [ ] Initialize Node.js project with Express
- [ ] Set up project directory structure (public/, src/, server/)
- [ ] Create .gitignore, .env.example with all required API keys
- [ ] Set up ESLint + Prettier for code quality
- [ ] Create GitHub Actions CI workflow for linting
- [ ] Initialize git repository and push to private GitHub repo
- [ ] Set up MongoDB Atlas free tier cluster
- [ ] Define MongoDB schemas (projects, assets_3d, assets_audio, board_cards, board_columns)
- [ ] Create base HTML shell with tab navigation
- [ ] Port NexHacks liquid glass CSS design system (variables, glassmorphism, animations, dark/light theme)
- [ ] Implement theme toggle (dark/light) with localStorage persistence
- [ ] Set up Express server with CORS, static file serving, and route structure

## Phase 1: Audio Tab (SFX Generator)
- [ ] Port fortnite-collab sfx-generator HTML/CSS/JS to new design system
- [ ] Adapt Express proxy route for ElevenLabs SFX API (/api/audio/sfx)
- [ ] Implement 10-variation parallel generation with staggered requests
- [ ] Build audio card grid with play/pause, status badges, download buttons
- [ ] Add download modal with custom filename input
- [ ] Connect to MongoDB: save generated audio metadata (prompt, duration, timestamp)
- [ ] Add audio history panel (list previous generations from MongoDB)
- [ ] Write tests for audio API routes

## Phase 2: Audio Tab (Voice Generation)
- [ ] Add voice generation section to Audio tab
- [ ] Implement ElevenLabs TTS API route (/api/audio/tts)
- [ ] Build voice selector UI (search/filter ElevenLabs voice library)
- [ ] Add dialogue batch input (multiple lines, generate all)
- [ ] Implement voice cloning UI (upload sample, create voice)
- [ ] Add ElevenLabs voice clone API route (/api/audio/voice-clone)
- [ ] Audio preview and download for generated dialogue
- [ ] Save voice/dialogue metadata to MongoDB
- [ ] Write tests for voice generation routes

## Phase 3: Models Tab (Core)
- [ ] Build Models tab UI: prompt input, provider toggle, generation controls
- [ ] Implement OpenRouter API route for prompt enhancement (/api/models/enhance-prompt)
- [ ] Implement Meshy text-to-3D API route (/api/models/generate/meshy)
- [ ] Implement Tripo3D text-to-3D API route (/api/models/generate/tripo)
- [ ] Implement Rodin text-to-3D API route (/api/models/generate/rodin)
- [ ] Add generation progress polling with status UI (Waiting/Generating/Ready/Error)
- [ ] Integrate three.js for in-browser GLB/FBX model preview
- [ ] Build orbit controls, grid floor, and lighting for 3D viewer
- [ ] Add download buttons (FBX, GLB, OBJ formats)
- [ ] Save model metadata to MongoDB (prompt, provider, format, polycount)
- [ ] Write tests for model generation routes

## Phase 4: Models Tab (Advanced)
- [ ] Add image-to-3D mode (upload reference image)
- [ ] Implement image upload to 3D API routes
- [ ] Add Roblox Open Cloud Assets upload (/api/models/upload-roblox)
- [ ] Build model history/gallery panel (grid of previous generations from MongoDB)
- [ ] Add model comparison view (side-by-side two providers for same prompt)
- [ ] Implement polycount/quality controls per provider
- [ ] Add negative prompt support (for providers that support it)
- [ ] Write tests for advanced model features

## Phase 5: Project Docs Tab
- [ ] Build Docs tab UI: file selector dropdown, content area, sidebar
- [ ] Implement filesystem read API route (/api/docs/read)
- [ ] Implement filesystem write API route (/api/docs/write)
- [ ] Integrate marked.js or similar for CommonMark markdown rendering
- [ ] Add highlight.js for code block syntax highlighting
- [ ] Build table of contents sidebar (auto-generated from headings)
- [ ] Implement section-level navigation (click to scroll)
- [ ] Add toggle between rendered view and raw editor
- [ ] Implement split-pane mode (editor + preview side by side)
- [ ] Add project switcher (detect Roblox project directories)
- [ ] Implement checkbox toggle (click `[ ]` to `[x]` and save)
- [ ] Write tests for docs API routes

## Phase 6: Trello Board Tab
- [ ] Build Trello tab UI: column containers, card components
- [ ] Implement drag-and-drop with SortableJS or vanilla HTML5 DnD
- [ ] Create MongoDB collections for board state (columns, cards)
- [ ] Implement CRUD API routes for cards (/api/board/cards)
- [ ] Implement CRUD API routes for columns (/api/board/columns)
- [ ] Build card creation modal (title, description, priority, labels, assignee)
- [ ] Build card detail/edit modal
- [ ] Add card filtering (by label, assignee, priority)
- [ ] Add card search
- [ ] Implement drag reordering persistence (save card positions to MongoDB)
- [ ] Set up MongoDB Change Streams for real-time sync between clients
- [ ] Write tests for board API routes

## Phase 7: Solana Integration
- [ ] Set up Solana wallet connection (Phantom adapter)
- [ ] Implement NFT minting for 3D assets via Metaplex (/api/solana/mint)
- [ ] Add "Mint as NFT" button to model cards in gallery
- [ ] Upload asset metadata to Arweave/IPFS
- [ ] Build simple asset marketplace view (browse minted assets)
- [ ] Implement Solana Pay for asset purchases
- [ ] Update MongoDB documents with on-chain data (mint address, owner)
- [ ] Write tests for Solana routes

## Phase 8: Vultr Deployment
- [ ] Create Dockerfile for the dashboard application
- [ ] Create docker-compose.yml (dashboard + nginx)
- [ ] Provision Vultr Cloud Compute instance
- [ ] Set up domain/subdomain with SSL (Let's Encrypt)
- [ ] Deploy via Docker Compose on Vultr
- [ ] Configure environment variables on server
- [ ] Set up Vultr firewall rules
- [ ] Test all features in production environment
- [ ] Set up basic monitoring (health check endpoint)

## Phase 9: Polish and Hackathon Prep
- [ ] Responsive design for all tabs (mobile/tablet breakpoints)
- [ ] Loading states and skeleton screens for all async operations
- [ ] Error handling with user-friendly toast notifications
- [ ] Keyboard shortcuts for common actions
- [ ] Onboarding tooltip/tour for first-time users
- [ ] Performance optimization (lazy load tabs, debounce inputs)
- [ ] Cross-browser testing
- [ ] Final design polish (consistent spacing, hover states, animations)
- [ ] Create demo content (sample models, audio, board cards)
- [ ] Record demo video/GIF for hackathon submission

---

# File Structure

```
DashBlox/
|
+-- PLAN.md
+-- PROGRESS.md
+-- README.md
+-- package.json
+-- .env.example
+-- .gitignore
+-- .eslintrc.json
+-- .prettierrc
+-- Dockerfile
+-- docker-compose.yml
|
+-- .github/
|   +-- workflows/
|       +-- lint.yml
|
+-- server/
|   +-- index.js                  # express entry point
|   +-- config.js                 # env vars, constants
|   +-- db.js                     # mongodb connection
|   +-- middleware/
|   |   +-- cors.js
|   |   +-- rateLimiter.js
|   |   +-- errorHandler.js
|   +-- routes/
|   |   +-- audio.js              # /api/audio/* (sfx, tts, voice-clone)
|   |   +-- models.js             # /api/models/* (generate, enhance, upload)
|   |   +-- docs.js               # /api/docs/* (read, write)
|   |   +-- board.js              # /api/board/* (cards, columns CRUD)
|   |   +-- solana.js             # /api/solana/* (mint, marketplace)
|   |   +-- assets.js             # /api/assets/* (roblox upload)
|   +-- services/
|   |   +-- openrouter.js         # openrouter api client
|   |   +-- elevenlabs.js         # elevenlabs api client
|   |   +-- meshy.js              # meshy 3d api client
|   |   +-- tripo.js              # tripo3d api client
|   |   +-- rodin.js              # rodin/hyper3d api client
|   |   +-- roblox.js             # roblox open cloud client
|   |   +-- solana.js             # solana/metaplex client
|   +-- models/
|   |   +-- Asset3D.js            # mongodb schema for 3d assets
|   |   +-- AssetAudio.js         # mongodb schema for audio assets
|   |   +-- BoardCard.js          # mongodb schema for board cards
|   |   +-- BoardColumn.js        # mongodb schema for board columns
|   |   +-- Project.js            # mongodb schema for projects
|
+-- public/
|   +-- index.html                # main SPA shell with tab navigation
|   +-- css/
|   |   +-- variables.css         # design tokens (colors, spacing, shadows)
|   |   +-- base.css              # reset, typography, glassmorphism utils
|   |   +-- layout.css            # header, tabs, main content areas
|   |   +-- models.css            # models tab styles
|   |   +-- audio.css             # audio tab styles
|   |   +-- docs.css              # docs tab styles
|   |   +-- board.css             # trello board styles
|   |   +-- components.css        # shared components (buttons, cards, modals)
|   +-- js/
|   |   +-- app.js                # tab switching, theme toggle, init
|   |   +-- api.js                # fetch wrapper for all API calls
|   |   +-- models.js             # models tab logic
|   |   +-- audio.js              # audio tab logic (sfx + voice)
|   |   +-- docs.js               # docs tab logic (render, edit, save)
|   |   +-- board.js              # trello board logic (dnd, CRUD)
|   |   +-- three-preview.js      # three.js model viewer
|   |   +-- markdown.js           # markdown rendering utilities
|   |   +-- solana.js             # wallet connection, minting UI
|   |   +-- theme.js              # dark/light theme management
|   |   +-- toast.js              # notification toasts
|   +-- assets/
|       +-- icons/                # svg icons for tabs, buttons
|       +-- fonts/                # inter font files (self-hosted)
|
+-- tests/
    +-- audio.test.js
    +-- models.test.js
    +-- docs.test.js
    +-- board.test.js
    +-- solana.test.js
```

---

# Risk Analysis

## Critical Risks

- **3D API rate limits / costs**: Free tiers are limited (Meshy ended free API access, Tripo gives 300 credits). Mitigation: implement provider toggle so user can switch when one provider's credits run out. Cache generated models in MongoDB to avoid re-generation. Roblox Cube is free but limited to beta.

- **ElevenLabs API costs**: SFX and TTS generation costs credits. Mitigation: show estimated cost before generation. Implement generation limits per session. Cache audio in MongoDB to replay without re-generating.

- **MongoDB Atlas free tier limits**: 512MB storage on M0. 3D model files and audio clips can fill this quickly. Mitigation: store actual asset files on Vultr Block Storage or local disk. MongoDB stores metadata + references only. Upgrade to M10 ($57/mo) if needed.

- **Solana complexity**: Blockchain integration adds significant complexity (wallet connection, transaction signing, on-chain state). Mitigation: implement as Phase 7 (last feature). Keep it optional. Use devnet for development. Minimal viable marketplace (mint + list + buy).

- **Three.js bundle size**: three.js is ~600KB minified. Mitigation: load it lazily only when Models tab is active. Use CDN for three.js to leverage browser caching.

- **Hackathon time pressure**: 9 phases is ambitious. Mitigation: phases are ordered by priority. Phase 0-3 (setup + audio + basic models) is the MVP. Phases 4-9 are enhancements. The dashboard is functional after Phase 3.

## Moderate Risks

- **Cross-browser 3D rendering**: three.js WebGL may have issues on older browsers. Mitigation: show a fallback message if WebGL is unavailable. Target Chrome/Firefox only.

- **File system access for Docs tab**: Reading/writing markdown files requires the dashboard server to have filesystem access to the Roblox project directories. Mitigation: configure project paths in .env. Validate paths server-side to prevent directory traversal.

- **Real-time sync for Trello board**: MongoDB Change Streams require a replica set (Atlas has this by default, but local dev doesn't). Mitigation: use polling fallback for local dev. Change Streams for production on Atlas.

---

# Development Guidelines

## Code Conventions
- Vanilla JavaScript (ES6+), no TypeScript for hackathon speed
- ESLint with standard rules + Prettier formatting
- Comments in lowercase with no trailing period: `// handles audio generation`
- No emojis in code, comments, or documentation
- CSS follows NexHacks design system (glassmorphism, CSS variables, Inter font)
- Server code uses Express router pattern with service layer separation
- All API routes return JSON with consistent shape: `{ success: boolean, data?: any, error?: string }`

## API Key Management
- All API keys stored in .env (never committed)
- .env.example lists all required keys with placeholder values:
  - OPENROUTER_API_KEY
  - ELEVENLABS_API_KEY
  - MESHY_API_KEY
  - TRIPO_API_KEY
  - RODIN_API_KEY
  - ROBLOX_API_KEY
  - MONGODB_URI
  - SOLANA_RPC_URL
  - SOLANA_PRIVATE_KEY (devnet only)
- Frontend never directly calls external APIs. All requests proxied through Express backend.

## Design System (from NexHacks)
- Dark theme default, light theme via `[data-theme="light"]`
- Primary background: `#000000`, secondary: `#0d0d0d`, tertiary: `#171717`
- Accent color: `#34d399` (emerald green)
- Glassmorphism: `backdrop-filter: blur(24px) saturate(200%)` with semi-transparent backgrounds
- Border radius: 8px (sm), 12px (md), 16px (lg), 20px (xl)
- Transitions: `0.3s cubic-bezier(0.25, 0.1, 0.25, 1)` (fast), `0.5s` (default)
- Font: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif
- Shadows: multi-layer with opacity scaling per theme

## Testing
- Jest for server-side API route testing
- Supertest for HTTP endpoint testing
- Test files in /tests/ directory
- Run tests before committing

---

# MongoDB Schema Details

## projects collection
```
{
  _id: ObjectId,
  name: string,
  path: string,                    // filesystem path to project root
  roblox_place_id: number | null,
  created_at: Date,
  updated_at: Date
}
```

## assets_3d collection
```
{
  _id: ObjectId,
  project_id: ObjectId,
  name: string,
  tags: [string],
  prompt: string,
  enhanced_prompt: string,
  provider: "meshy" | "tripo" | "rodin" | "roblox-cube",
  provider_task_id: string,
  status: "pending" | "generating" | "ready" | "error",
  format: "fbx" | "glb" | "obj",
  file_path: string,              // local path to downloaded model
  thumbnail_path: string,
  polycount: number,
  roblox_asset_id: number | null,
  solana_mint: string | null,
  created_at: Date
}
```

## assets_audio collection
```
{
  _id: ObjectId,
  project_id: ObjectId,
  name: string,
  type: "sfx" | "tts" | "voice-clone",
  tags: [string],
  prompt: string,
  voice_id: string | null,
  voice_name: string | null,
  model: string,
  duration_seconds: number,
  format: "mp3",
  file_path: string,
  roblox_asset_id: number | null,
  created_at: Date
}
```

## board_columns collection
```
{
  _id: ObjectId,
  project_id: ObjectId,
  title: string,
  position: number,
  created_at: Date
}
```

## board_cards collection
```
{
  _id: ObjectId,
  column_id: ObjectId,
  project_id: ObjectId,
  title: string,
  description: string,
  priority: "low" | "medium" | "high" | "critical",
  labels: [string],
  assignee: string | null,
  due_date: Date | null,
  linked_asset_id: ObjectId | null,
  position: number,
  created_at: Date,
  updated_at: Date
}
```

---

# API Route Reference

## Audio Routes (/api/audio)
- `POST /api/audio/sfx` - generate sound effect via ElevenLabs
- `POST /api/audio/tts` - generate text-to-speech via ElevenLabs
- `POST /api/audio/voice-clone` - create voice clone from audio sample
- `GET /api/audio/voices` - list available ElevenLabs voices
- `GET /api/audio/history` - list previous audio generations from MongoDB

## Models Routes (/api/models)
- `POST /api/models/enhance-prompt` - enhance user prompt via OpenRouter
- `POST /api/models/generate` - generate 3D model (provider specified in body)
- `GET /api/models/status/:taskId` - poll generation status
- `GET /api/models/download/:taskId` - download generated model file
- `POST /api/models/upload-roblox` - upload model to Roblox via Open Cloud
- `GET /api/models/history` - list previous model generations from MongoDB

## Docs Routes (/api/docs)
- `GET /api/docs/projects` - list available Roblox projects
- `GET /api/docs/read` - read a markdown file (query: project, file)
- `PUT /api/docs/write` - write/update a markdown file

## Board Routes (/api/board)
- `GET /api/board/columns` - list all columns for a project
- `POST /api/board/columns` - create a new column
- `PUT /api/board/columns/:id` - update column (title, position)
- `DELETE /api/board/columns/:id` - delete column
- `GET /api/board/cards` - list all cards (optional: filter by column, label, assignee)
- `POST /api/board/cards` - create a new card
- `PUT /api/board/cards/:id` - update card (title, description, column, position)
- `DELETE /api/board/cards/:id` - delete card
- `PUT /api/board/cards/:id/move` - move card to different column + position

## Solana Routes (/api/solana)
- `POST /api/solana/mint` - mint a 3D/audio asset as NFT
- `GET /api/solana/marketplace` - list minted assets
- `POST /api/solana/purchase` - initiate Solana Pay transaction

## Assets Routes (/api/assets)
- `POST /api/assets/upload-roblox` - upload any asset to Roblox Open Cloud
- `GET /api/assets/:id` - get asset details from MongoDB

---

# External API Integration Details

## Gemini via OpenRouter (LLM Backbone)
- Base URL: `https://openrouter.ai/api/v1/chat/completions`
- Auth: `Authorization: Bearer OPENROUTER_API_KEY`
- Primary model: `google/gemini-2.0-flash` (hackathon sponsor, fast + cheap)
- Fallback models:
  - `google/gemini-2.5-pro` for complex prompt enhancement
  - `meta-llama/llama-3.1-8b-instruct:free` for quick/cheap operations
  - `openrouter/auto` for automatic routing
- Use cases:
  - 3D prompt enhancement (refine user prompts for Meshy/Tripo/Rodin)
  - Luau code generation (game scripts, NPC behaviors)
  - Game design assistance (feed PLAN.md, suggest next steps)
  - Zombie AI behavior trees, wave difficulty curves
- Structured output via `response_format` for consistent 3D prompt formatting

## ElevenLabs (Audio Generation)
- SFX endpoint: `POST https://api.elevenlabs.io/v1/sound-generation`
- TTS endpoint: `POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id}`
- Voice clone: `POST https://api.elevenlabs.io/v1/voices/add`
- Voice list: `GET https://api.elevenlabs.io/v1/voices`
- Auth: `xi-api-key: ELEVENLABS_API_KEY`

## Meshy (3D Generation)
- Text-to-3D: `POST https://api.meshy.ai/openapi/v2/text-to-3d`
- Status: `GET https://api.meshy.ai/openapi/v2/text-to-3d/{id}`
- Image-to-3D: `POST https://api.meshy.ai/openapi/v1/image-to-3d`
- Auth: `Authorization: Bearer MESHY_API_KEY`
- Two-stage: preview (base mesh) then refine (textured)

## Tripo3D (3D Generation)
- Create task: `POST https://api.tripo3d.ai/v2/openapi/task`
- Check status: `GET https://api.tripo3d.ai/v2/openapi/task/{task_id}`
- Auth: `Authorization: Bearer TRIPO_API_KEY`
- Task types: `text_to_model`, `image_to_model`

## Rodin/Hyper3D (3D Generation)
- Generate: `POST https://api.hyper3d.com/api/v2/rodin`
- Auth: `Authorization: Bearer RODIN_API_KEY`
- Supports multipart/form-data for image uploads
- Quality tiers: Sketch, Regular, Detail, Smooth

## Roblox Open Cloud (Asset Upload)
- Upload: `POST https://apis.roblox.com/assets/v1/assets`
- Auth: `x-api-key: ROBLOX_API_KEY`
- Multipart form: request (JSON metadata) + fileContent (model file)
- Supported: model/fbx, model/gltf-binary

## Solana
- RPC: Solana mainnet/devnet JSON-RPC
- NFT minting: Metaplex Token Metadata program
- Payments: @solana/pay SDK
- Wallet: @solana/wallet-adapter for Phantom connection

---

# References

- fortnite-collab SFX Generator: `/home/matheus/projects/Roblox/fortnite-collab/tools/sfx-generator/`
- NexHacks Design System: `/home/matheus/projects/NexHacks/frontend/css/styles.css`
- Meshy API Docs: https://docs.meshy.ai/en/api/text-to-3d
- Tripo3D API Docs: https://platform.tripo3d.ai/docs/quick-start
- Rodin API Docs: https://developer.hyper3d.ai/api-specification/rodin-generation
- Roblox Open Cloud Assets: https://create.roblox.com/docs/reference/cloud/assets/v1
- Roblox Cube 3D Beta: https://devforum.roblox.com/t/beta-cube-3d-generation-tools-and-apis-for-creators/3558947
- OpenRouter API: https://openrouter.ai/docs/api/reference/overview
- ElevenLabs API: https://elevenlabs.io/docs/api-reference/text-to-speech/convert
- ElevenLabs SFX: https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert
- MongoDB Change Streams: https://www.mongodb.com/docs/manual/changestreams/
- Metaplex NFT Guide: https://developers.metaplex.com/token-metadata/guides/javascript/create-an-nft
- Solana Pay: https://docs.solanapay.com/
- three.js: https://threejs.org/docs/
- SortableJS: https://sortablejs.github.io/Sortable/
- marked.js: https://marked.js.org/

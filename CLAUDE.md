# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git Conventions

### Commits
- Do NOT include `Co-Authored-By: Claude` or any co-author attribution
- All commits must be authored by `@matheusmaldaner`
- Keep messages simple, no colons, no prefixes like `fix:` or `feat:`
- Examples:
  - `add localStorage support for info persistence on page refresh`
  - `add a sidebar to display overshoot logs`

### Branches
- Use hyphen-separated names: `add-user-authentication`, `fix-login-bug`
- Do NOT use prefixes like `feature/`, `bugfix/`, `hotfix/`

### Pull Requests
- Always create as draft
- Do NOT auto-request reviewers
- Check for any open issues in the project before starting work
- All PRs must be authored by `@matheusmaldaner`, not Claude
- Use regular merge commits (not squash or rebase)
- Fix merge conflicts iteratively

Format:
- **Title:** `<description> #<PR-number>`
- **Body:** List files changed with descriptions, reference related PRs when relevant

Examples:
```
Title: establish docker entrypoint + novnc + cdp ports #1
Body:
docker-compose.yaml, Dockerfile and start-browser.sh created to establish connection with ports for VNC + CDP (currently unused)
```

```
Title: basic frontend implementation #2
Body:
added simple README.md
minor path fixes
add .css, .html, .js for the landing page
integrate with ports predefined in PR establish docker entrypoint + novnc + cdp ports #1
```

```
Title: sidebar and storage integration #4
Body:
sidebar.css, sidebar.js, index.html: adds a sidebar to the frontend to showcase overshoot logs
storage.js: add localStorage() support to persist data upon page refresh
overshoot.js: integrates with @aamoghS's previous PR global array #3
```

## Repository Setup

When starting a new project:
1. Create a private GitHub repository (ensure it stays private)
2. Set up CI/CD workflows for testing and linting
3. Configure `.gitignore` to exclude `.env` but include `.env.example`
4. Establish test infrastructure early and expand coverage as the project grows

## Code Style

### Comments
- Use lowercase with no trailing period: `// iterates through file`
- NOT capitalized: `// Iterate through file`

### General Principles
- Prefer simpler code that is easier to understand
- Keep the codebase clean and organized
- No emojis anywhere in code, comments, documentation, or commits
- No default language or framework unless specified by the user

### UI Design
- Minimalistic and clean design (Apple liquid glass aesthetic)
- Reference design system: `projects/NexHacks/frontend/css/styles.css`
- Dark/light theme support with CSS variables
- Smooth transitions and subtle animations
- Glassmorphism with backdrop blur effects

## Documentation

- README.md should be brief and to the point
- No tables in documentation
- No emojis
- Do NOT create additional .md files
- Only modify PLAN.md and PROGRESS.md for project tracking

## Environment

- `.env` - ignored, never committed
- `.env.example` - committed, contains placeholder values for required variables

## Testing and Quality

- Always write tests for new code
- Establish linting workflows at the beginning of the project
- Increment test coverage as the project grows
- Cover all edge cases
- Ensure tests and linting pass before committing

## Workflow

### Decision Making
- Present numbered options for the user to choose from at decision points
- Do not proceed with ambiguous requests without clarification
- Summarize terminal output rather than showing full logs

### Planning
- Start with planning before execution to avoid downstream issues
- Use PLAN.md to document what will be built
- Use PROGRESS.md to track what has been completed

### Verification
- Always verify work through tests, linting, or other domain-specific methods
- Run the test suite before considering a task complete

## PLAN.md Format

```markdown
# Project Name

**Project**: Brief description
**Duration**: Timeline
**Team Size**: N members

> **Current Status**: See [PROGRESS.md](./PROGRESS.md) for live tracking.

---

# Project Overview

## The Problem
1. Problem statement 1
2. Problem statement 2

## The Solution
Description of what the project does.

---

# Core Features

## 1. Feature Name
Description and implementation details.

## 2. Feature Name
Description and implementation details.

---

# Technical Architecture

(ASCII diagram of system components and data flow)

---

# Implementation Phases

## Phase 0: Setup
- [ ] Task 1
- [ ] Task 2

## Phase 1: Core Functionality
- [ ] Task 1
- [ ] Task 2

## Phase N: Polish
- [ ] Task 1
- [ ] Task 2

---

# File Structure

(Tree view of project structure)

---

# Risk Analysis

## Critical Risks
- Risk 1: Description + Mitigation
- Risk 2: Description + Mitigation

---

# Development Guidelines

(Project-specific coding conventions)

---

# References

- Link 1
- Link 2
```

## PROGRESS.md Format

```markdown
# Project Name - Progress

> **Living Memory Document**: Updated at every development step.

---

## Current Status

- **Project**: Name
- **Phase**: Current phase
- **Current Task**: What's being worked on
- **Last Updated**: Timestamp
- **Tests Passing**: Yes/No

---

## Service Status

- Service 1: Port X - Status
- Service 2: Port Y - Status

---

## Phase Checklist

### Phase 0: Setup
- [x] Completed task
- [ ] Pending task

### Phase 1: Core
- [ ] Task 1
- [ ] Task 2

---

## Completed Tasks

- Task 1 - Time - Notes
- Task 2 - Time - Notes

---

## Decisions Log

- Decision 1 - Rationale - Time
- Decision 2 - Rationale - Time

---

## Risk Register

- Risk 1 - Severity - Mitigation - Status
- Risk 2 - Severity - Mitigation - Status

---

## Session Notes

### Session: Date
**Completed**: List of completed items
**Current State**: Description
**Next Steps**: What to do next

---

## Quick Reference

### Commands
(Common commands for the project)

### Important Links
- Link 1
- Link 2
```

## Projects

When starting a session in the projects root directory (/home/matheus/projects), automatically:
1. Explore all subdirectories to identify projects
2. For each project, note: Purpose (one sentence), Main language/framework, Reusable patterns
3. Update this section with findings

### Current Projects Summary

**Hackathon & Competition Projects**
- **NexHacks** - AI learning companion that observes study habits and generates quizzes (Python/FastAPI + JS)
- **PlatosCave** - UF AI Days winner: Human-centered research validation with knowledge graphs (Python/Gatsby/Docker)
- **ArtCompetitionUF** - AI art generation using CUDA and Replicate (Python/AI Models)
- **Roblox** - Hackathon workspace with planning/progress templates (Markdown)

**Research & Academic**
- **AppliedMachineLearning** - UF ML course materials with pipeline templates (Python/Jupyter)
- **Thesis** - Undergrad thesis tools: DiffLogic visualizer, EcoLogic, SaliencySlider (Python/Research)
- **WoodardAmazon** - Amazon internship: DeepUnrollNet, rolling shutter correction (Python/Deep Learning)
- **CompressionTokens** - Testing 200+ token compression algorithms for LLMs (Python/Research)
- **SalgadoAISystems** - SentinelBench for AI safety evaluation (Python/TypeScript)
- **VisualizerDemos** - ML visualization demos: CNN/transformer explainers (Python/Web)

**Web Development**
- **PersonalWebsite** - Portfolio with GitHub Pages and video generation (JavaScript/Jekyll)
- **DSIWebsite** - UF Data Science & Informatics website (Node.js)
- **magentic-ui** - AI-assisted UI generation framework (Python/React/Gatsby)
- **MagenticUI-BlogpostReady** - Blog-ready Magentic-UI version (JavaScript/React/Gatsby)
- **GasTown** - Gatsby web application (JavaScript/Gatsby)

**Tools & Utilities**
- **PaperParser** - Academic paper analysis with web scraping (Python/React)
- **AnkiGarmin** - Anki flashcards for Garmin smartwatch (MonkeyC/Garmin Connect IQ)
- **CR2toPNG** - Canon CR2 to PNG converter (Shell Script)
- **CalendarAAIG** - AAIG calendar event scraper (Python)
- **llmapi** - LLM integration API with SentinelSearcher (Python/API)

**AI & Machine Learning**
- **agent-sandbox** - Multi-agent LLM game world with visual perception (Python/TypeScript)
- **FinsOliviaRL** - RL performance analysis for finance (Python/RL)
- **CarnegieMellon** - WeAudit projects for AI content auditing (Python/Flask)

**Mobile & Security**
- **SurvivorPhone** - Android APK analysis and mobile security (Mobile Security)

**Practice & Learning**
- **leetcode** - Algorithm practice and interview prep (Python)
- **test** - Applied ML project materials (Python/Testing)

### Reusable Patterns & Components

**UI/Design System**
- Liquid glass aesthetic CSS (NexHacks: `frontend/css/styles.css`)
- Dark/light theme variables with glassmorphism effects
- Gatsby + React templates for rapid prototyping

**Backend Architecture**
- FastAPI + WebSocket patterns for real-time features (NexHacks)
- Flask blueprints for modular API design (CarnegieMellon)
- Docker compose setups for multi-service apps (PlatosCave, NexHacks)

**AI/ML Pipelines**
- Research paper validation workflows (PlatosCave)
- Token compression testing framework (CompressionTokens)
- Visualization components for ML explainability (VisualizerDemos)

**Development Workflows**
- Hackathon planning templates: PLAN.md, PROGRESS.md (Roblox)
- Git conventions: simple commit messages, no prefixes
- Testing infrastructure patterns from Applied ML course

## Notifications

To receive desktop notifications when Claude needs input, add this to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "notify-send 'Claude Code' 'Awaiting your input' -u critical"
          }
        ]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "notify-send 'Claude Code' 'Permission required' -u critical"
          }
        ]
      }
    ]
  }
}
```

Notification types:
- `idle_prompt` - Claude is waiting for user input
- `permission_prompt` - Claude needs permission to run something

## Build Commands

```bash
# rojo (roblox game sync)
rojo serve                    # start rojo dev server (connect from roblox studio)
rojo build -o game.rbxl       # build place file

# dashboard (cd dashboard/ first)
cd dashboard
npm install                   # install dependencies
npm run dev                   # start dev server (port 3000, auto-reload)
npm start                     # start production server
npm test                      # run tests
npm run lint                  # lint code
npm run format                # format code
```

## Architecture

### Repo Layout
- `src/` - roblox game source (luau, synced via rojo)
- `dashboard/` - web dashboard (node.js express + vanilla frontend)
- `default.project.json` - rojo project config
- `aftman.toml` - toolchain manager (rojo 7.6.1)

### Rojo (Game)
- Rojo 7.6.1 via aftman for studio sync
- `src/server/` -> ServerScriptService
- `src/client/` -> StarterPlayer.StarterPlayerScripts
- `src/shared/` -> ReplicatedStorage
- Luau files with `.server.luau`, `.client.luau`, `.luau` extensions

### Dashboard (Web App)
**Stack**: Vanilla HTML/CSS/JS frontend + Node.js Express backend
**Database**: MongoDB Atlas (free tier M0, upgrade to M10 for production)
**Hosting**: Vultr Cloud Compute (vc2-2c-4gb)

#### Frontend
- Vanilla HTML/CSS/JS (no framework, no build step)
- NexHacks liquid glass design system (dark/light theme, glassmorphism)
- three.js for 3D model preview (loaded lazily on Models tab)
- SortableJS for Trello board drag-and-drop
- marked.js + highlight.js for markdown rendering

#### Backend (Node.js Express)
- Static file serving for frontend
- API proxy routes to external services (never expose API keys to client)
- Route structure: /api/audio/*, /api/models/*, /api/docs/*, /api/board/*, /api/solana/*
- Service layer: each external API has a dedicated service module
- Middleware: CORS, rate limiting, error handling

### External APIs
- **Gemini (via OpenRouter)**: primary LLM for prompt enhancement, code generation
- **OpenRouter**: LLM routing with fallback (Gemini -> Claude -> Llama)
- **ElevenLabs**: SFX generation, TTS, voice cloning
- **Meshy/Tripo/Rodin**: 3D model generation (multi-provider toggle)
- **Roblox Open Cloud**: asset upload to Roblox
- **Solana/Metaplex**: NFT minting, asset marketplace (optional)

### Database (MongoDB Atlas)
- Collections: projects, assets_3d, assets_audio, board_columns, board_cards
- Change Streams for real-time Trello board sync
- Metadata only (asset files stored on disk / Vultr Block Storage)

### Dashboard Tabs
1. **Models** - AI 3D model generation with multi-provider toggle
2. **Audio** - ElevenLabs SFX + voice generation (ported from fortnite-collab)
3. **Docs** - CLAUDE.md / PLAN.md / PROGRESS.md viewer/editor
4. **Board** - Kanban task manager with drag-and-drop

### Hackathon Framing
- **Pitch**: "An AI-powered Roblox game development dashboard that we used to build a Zombies game in record time"
- Dashboard IS the hackathon project
- Zombies game (fortnite-collab/Zombies) is PROOF it works
- Sponsors: Gemini (AI backbone), ElevenLabs (audio), MongoDB (data), Vultr (hosting), Solana (optional economy)

## Environment Variables

Required in `dashboard/.env` (see `dashboard/.env.example` for placeholders):
- `PORT` - server port (default 3000)
- `OPENROUTER_API_KEY` - OpenRouter API key (routes to Gemini, Claude, Llama)
- `ELEVENLABS_API_KEY` - ElevenLabs API key
- `MESHY_API_KEY` - Meshy 3D generation API key
- `TRIPO_API_KEY` - Tripo3D API key
- `RODIN_API_KEY` - Rodin/Hyper3D API key
- `ROBLOX_API_KEY` - Roblox Open Cloud API key
- `MONGODB_URI` - MongoDB Atlas connection string
- `SOLANA_RPC_URL` - Solana RPC endpoint (devnet for dev, mainnet for prod)
- `SOLANA_PRIVATE_KEY` - Solana wallet private key (devnet only, never mainnet)
- `PROJECT_PATHS` - comma-separated paths to Roblox project directories for Docs tab

## Related Projects

- **fortnite-collab**: `/home/matheus/projects/Roblox/fortnite-collab/` - main Roblox game with SFX generator tool to port
- **Zombies**: `/home/matheus/projects/Roblox/Zombies/` - wave-based survival game (proof-of-concept for dashboard)
- **NexHacks**: `/home/matheus/projects/NexHacks/` - design system reference (CSS in `frontend/css/`)
- **FortBox**: `/home/matheus/projects/Roblox/FortBox/` - hackathon variant
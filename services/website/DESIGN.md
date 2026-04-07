# Quantroot Website Design Document

This document describes the website's design, layout, structure, and
terminology so that changes can be communicated precisely.

## Tech Stack

- **Framework**: Astro (static site generator)
- **Styling**: Tailwind CSS 4 (utility-first, via `@tailwindcss/vite` plugin)
- **Fonts**: Inter (sans), JetBrains Mono (mono) — loaded from Google Fonts
- **Build**: `npx astro build` → static HTML in `dist/`
- **Dev**: `npx astro dev` or `make dev-website` from monorepo root

## File Structure

```
services/website/
├── public/
│   └── favicon.svg          QR logo (orange Q, purple R, dark rounded rect)
├── src/
│   ├── layouts/
│   │   └── Layout.astro     Base HTML shell (head, meta, fonts, body)
│   ├── pages/
│   │   ├── index.astro      Landing page — assembles components in order
│   │   └── wallet.astro     Wallet guide page — step-by-step RPC guide
│   ├── components/
│   │   ├── Nav.astro        Fixed top nav bar
│   │   ├── Hero.astro       Landing hero section
│   │   ├── QuickStart.astro 5-command smoke test + stats
│   │   ├── HowItWorks.astro 4-step quantum insurance explainer
│   │   ├── BIPs.astro       4-card BIP overview grid
│   │   ├── ScriptExample.astro  Annotated hybrid script code block
│   │   ├── WalletConstructions.astro  2-card construction comparison
│   │   ├── Benchmarks.astro Performance bars + test coverage stats
│   │   ├── Architecture.astro  Expandable design decision FAQ
│   │   └── Footer.astro     Links and license
│   └── styles/
│       └── global.css       Theme colors, fonts, smooth scroll
├── astro.config.mjs         Astro + Tailwind plugin config
└── package.json             Dependencies
```

## Color Palette

Defined as CSS custom properties in `global.css` via `@theme {}`:

| Token | Hex | Usage |
|-------|-----|-------|
| `btc-orange` | `#f7931a` | Bitcoin branding, Schnorr-related elements, BIP 368 |
| `btc-orange-dark` | `#e2820a` | Hover state for orange buttons |
| `quantum` | `#8b5cf6` | SPHINCS+/quantum-related elements, BIP 369 |
| `quantum-dark` | `#7c3aed` | Hover state for purple elements |
| `surface` | `#0a0a0f` | Page background (near-black) |
| `surface-raised` | `#12121a` | Card backgrounds, code blocks |
| `surface-overlay` | `#1a1a26` | Hover backgrounds, progress bars |
| `border` | `#2a2a3a` | Card borders, section dividers |
| `text-primary` | `#e4e4ed` | Headings, strong text, code keywords |
| `text-secondary` | `#9494a8` | Body text, descriptions, labels |

**Color convention**: Orange for Schnorr/key-path/BIP 368 elements. Purple
for SPHINCS+/quantum/BIP 369 elements. This maps to the dual-signature
nature of the hybrid script.

## Typography

| Token | Font | Usage |
|-------|------|-------|
| `font-sans` | Inter | Body text, headings, UI elements |
| `font-mono` | JetBrains Mono | Code blocks, hex values, CLI commands, opcodes |

## Favicon

SVG favicon at `public/favicon.svg`: Dark rounded rectangle with "QR" text.
The "Q" is orange (`btc-orange`), the "R" is purple (`quantum`).

## Layout

Dark theme. Max content width `max-w-6xl` (1152px) for most sections,
`max-w-3xl`/`max-w-4xl` for focused content (code blocks, benchmarks).

Responsive breakpoint: `md:` (768px). Desktop shows side-by-side grids,
mobile stacks vertically.

## Pages

### Landing Page (`index.astro`)

Single-page scroll with sections in this order:

1. **Nav** (fixed top)
2. **Hero**
3. **QuickStart**
4. **HowItWorks**
5. **BIPs**
6. **ScriptExample**
7. **WalletConstructions**
8. **Benchmarks**
9. **Architecture**
10. **Footer**

### Wallet Guide (`wallet.astro`)

Multi-section tutorial page with Nav and Footer. Sections:

1. Create a Wallet
2. Create a SPHINCS+ Key
3. Generate a Quantum-Insured Address
4. Export the Quantum-Insured Extended Key
5. Import into a Watch-Only Wallet
6. Quantum-Insured Extended Keys (qpub/qprv format table)
7. Seed-Derived SPHINCS+ Keys (HMAC derivation)
8. Encrypted Wallet Support (locked/unlocked operation table)
9. Descriptor Syntax (qr() primary, qis() advanced)
10. Hybrid Script Anatomy (annotated code + normal/emergency panels)
11. Available RPCs (reference table)

## Component Reference

### Nav

Fixed top bar with backdrop blur. Contains:
- **Logo**: Orange "Q" + white "uantroot" (`tracking-tight`)
- **Desktop nav links**: text links for section anchors + "Wallet Guide" page link
- **GitHub button**: bordered pill with octocat SVG icon
- **Mobile hamburger**: toggle button with open/close SVG icons, slide-down menu

Links array in frontmatter: `{ label, href }`. Page links use `/wallet`,
section links use `#how-it-works`, `#bips`, `#benchmarks`.

GitHub URL: `https://github.com/cmdruid/bitcoin/tree/quantroot`

### Hero

Full-width section with radial gradient background (purple, 10% opacity).
Contains:
- **Status pill**: pulsing purple dot + "Proof of Concept — BIP 368 & BIP 369"
- **Headline**: "Post-Quantum Security for Bitcoin Taproot" (orange "Bitcoin")
- **Tagline**: paragraph about SPHINCS+ and zero-cost quantum insurance
- **CTA buttons**: "Learn How It Works" (orange fill) + "View on GitHub" (bordered)

### QuickStart

Compact section between Hero and HowItWorks. Contains:
- **Heading**: "Get Started in 5 Commands"
- **Code block**: 5 `bitcoin-cli` commands with `$` prompt, purple-highlighted
  RPC names, orange string literals
- **Stats row**: 3 cards showing "7 New RPCs", "170 Tests Passing", "0 Breaking Changes"

### HowItWorks

4-step explainer in a 2x2 grid (`md:grid-cols-2`). Each card has:
- **Step number**: purple mono text (`01`, `02`, `03`, `04`)
- **Title**: bold heading
- **Description**: paragraph explaining the step
- **Detail**: italic secondary text with technical specifics

Cards have `hover:border-quantum/40` effect. Steps describe the quantum
insurance lifecycle: create → spend → threat → redeem.

Section heading: "Quantum Insurance for Your Bitcoin"

### BIPs

4 BIP cards in a 2x2 grid. Each card has:
- **Tag pill**: colored badge ("Key-path protection", "Script-path protection", "Wallet layer")
- **Title**: "BIP 368: Key-Path Hardening" format
- **Bullet points**: 5 items per card with colored dots

First row: consensus BIPs (368 orange, 369 purple).
Second row: wallet BIPs (395 purple, 377 orange).

Section heading: "Four Companion BIPs"

### ScriptExample

Annotated code block showing the hybrid Tapscript. Contains:
- **Code block header**: "Tapscript template" label
- **Numbered lines**:
  - Line 1: `<sphincs_pk>` (purple) + `OP_CHECKSPHINCSVERIFY OP_DROP`
  - Line 2: `<schnorr_pk>` (orange) + `OP_CHECKSIG`
- **Two annotation panels** (side by side on desktop):
  - Left (orange dot): "Non-upgraded nodes" — explains OP_NOP4 behavior
  - Right (purple dot): "Upgraded nodes" — explains dual verification
- **Signing order note**: italic text below the block

### WalletConstructions

2 construction cards side by side. Each has:
- **Name + recommended badge**: "Hybrid Leaf + Key-Path" with purple "Recommended" tag
- **Subtitle**: secondary description
- **Description**: paragraph
- **Structure block**: dark mono code showing the Taproot tree layout
- **Pros/cons list**: green `+` for pros, orange `-` for cons

Card 1 (recommended): real internal key + hybrid leaf.
Card 2 (alternative): NUMS + separate Schnorr/hybrid leaves.

### Benchmarks

3 performance bars + validation weight note + test coverage grid. Each bar has:
- **Label**: operation name (left)
- **Time + ratio**: mono text (right) with purple ratio badge
- **Progress bar**: gradient from purple to orange

Test coverage section: 3 stat cards showing consensus/unit/functional test counts.

### Architecture

Expandable FAQ with `<details>` elements. Each has:
- **Summary**: question text with `+` icon that rotates to `×` on open
- **Content**: answer paragraph in secondary text

Hover effect: `hover:border-quantum/30`.

### Footer

Centered text with license note and links to GitHub, BIPs, NIST FIPS 205.

## Conventions

### Section pattern
Each section component is a `<section>` with:
- `border-t border-border` top separator
- `py-20 md:py-28` vertical padding
- `mx-auto max-w-5xl px-6` centered content container
- Centered heading (`text-center`) + subtitle paragraph
- Content grid or card layout below

### Card pattern
Cards use:
- `rounded-xl border border-border bg-surface-raised p-6` (or `p-8`)
- Optional `hover:border-quantum/40` or `hover:border-quantum/30` interaction

### Code block pattern
Code blocks use:
- `rounded-lg bg-surface-raised` or `rounded-xl border border-border bg-surface-raised overflow-hidden`
- Header bar with label: `border-b border-border px-5 py-3`
- Content area: `px-6 py-5 font-mono text-sm leading-relaxed overflow-x-auto`
- Colored tokens: `text-quantum` for SPHINCS+, `text-btc-orange` for Schnorr,
  `text-text-primary font-medium` for opcodes

### Data-driven pattern
Most components define their content as JavaScript arrays in the Astro
frontmatter (`---` block), then iterate with `.map()` in the template.
This separates content from presentation.

To change content: edit the array in the frontmatter.
To change layout: edit the HTML template below the `---` block.

## How to Make Changes

### Change section content
Edit the data array in the component's frontmatter. For example, to add a
BIP card, add an entry to the `bips` array in `BIPs.astro`.

### Change section layout
Edit the HTML template in the component. Tailwind classes control all
styling. Use the color tokens above for consistency.

### Add a new section to the landing page
1. Create `src/components/NewSection.astro`
2. Import it in `src/pages/index.astro`
3. Add `<NewSection />` in the desired position within `<main>`

### Add a new page
1. Create `src/pages/newpage.astro`
2. Import Layout, Nav, Footer
3. Add a nav link in `Nav.astro`'s `links` array

### Change colors
Edit `src/styles/global.css` `@theme {}` block. All components reference
the color tokens, so changes propagate everywhere.

### Change fonts
Edit the Google Fonts URL in `Layout.astro` and the `@theme {}` font tokens.

## Build & Preview

```bash
# From services/website/
npx astro dev          # Dev server at http://localhost:4321
npx astro build        # Production build to dist/

# From monorepo root
make dev-website       # Same as npx astro dev
```

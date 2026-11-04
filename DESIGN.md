# Squeek Wars Testnet: design system

Taken from the source: `web/src/styles.css` (tokens and all component CSS), `web/src/ui.tsx`,
`web/src/tx.tsx`, `web/src/wallet.tsx` and `web/src/main.tsx` (font imports). The site is built into `dist/`.

## Overview

A browser game for Sepolia players, styled as a pixel-art hamster village: warm wood, straw and stone,
square corners, and chunky framed buttons with hard pixel shadows. Pages are dense, with
information first. Each page is a grid of framed panels holding live numbers, countdowns and one
clear action per row. The header is dark wood, the nav darker wood, and the Squeektoshi strip is a
straw band that stays on every page. Content sits on a paper surface over a light straw background.

## Colors

All colors are custom properties in `:root` of `web/src/styles.css`. Primitives are named by material.
Components use the role tokens.

| Role token | Value | Use |
| --- | --- | --- |
| `--bg` | `--straw-50` `#fbf3dc` | page background |
| `--surface` | `--paper` `#fffaf0` | panels, cards, sheets, tx toasts |
| `--surface-sunk` | `--straw-100` `#f3e2b3` | rows inside panels (plots, slots, reports, troops), tabs, empty states |
| `--text` | `--wood-900` `#2e1c0e` | body text, button edges |
| `--text-muted` | `--stone-600` `#5f5b55` | secondary text, `.muted`, `.hint`, `dt` |
| `--frame` | `--wood-700` `#5a3a1e` | 3px panel/card/sheet borders, header background |
| `--action` / `--action-hover` | `--wood-500` `#8a5a2b` / `--wood-400` `#a36d38` | primary buttons |
| `--on-action` | `--straw-50` | text on primary buttons |
| `--danger` | `--berry-700` `#93281f` | danger button, reverted tx, `.hint.bad` |
| `--ok` | `--leaf-700` `#335a22` | confirmed tx |
| `--focus` | `--sky-700` `#1d4fa0` | focus outlines, links |

The nav uses `--wood-800` `#432a15`, and the Squeektoshi strip `--straw-200` `#e8cf8f`. Four literal
values exist only for single purposes: `#e3ead0` (finished research tier), `#f8e6a8` (your row in
Ranking), `#ad3a2f` (danger hover), and the map palette in `web/src/pages/Map.tsx` (grass
`#cfe0a0`/`#c4d896`, camps `#7a5a3a`, villages `#b5462e`, you `#f2c230`, selection `#1d4fa0`). No contrast ratios have been measured. See the validation notes in README.md.

## Typography

- `--font-pixel`: "Pixelify Sans" (bundled from `@fontsource/pixelify-sans`, weights 500 and 700,
  WOFF2/WOFF in `dist/assets/`), falling back to `ui-rounded, system-ui, sans-serif`. Used for headings, buttons,
  nav, tabs, the brand and big resource numbers.
- `--font-body`: the system UI stack, for body text, inputs and connect-sheet rows.
- `--font-mono`: for addresses (`.addr`, `.mono`) at `--fs-1`.
- One scale of six sizes: `--fs-1` 14px (small print, addresses, tables), `--fs-2` 16px (body,
  inputs, nav, small buttons), `--fs-3` 18px (buttons, card titles, lead), `--fs-4` 22px (panel
  titles, brand, resource numbers), `--fs-5` 28px (page titles), `--fs-6` 36px (desktop hero; drops to
  `--fs-5` at 640px or narrower).
- Body line-height is 1.5 and headings 1.15. Headings use `text-wrap: balance` and paragraphs `pretty`.
  Numbers that tick or line up use `.num` (tabular figures). No letter-spacing and no uppercase labels.

## Layout

- Spacing runs on a 4px grid: `--s-1` 4, `--s-2` 8, `--s-3` 12, `--s-4` 16, `--s-5` 24, `--s-6` 32. `--px` 3px
  is the pixel border unit.
- `main` is at most 1200px wide, centred, with `--s-4` padding (`--s-3` at 640px or narrower). Text pages (`.doc`) are at most 760px
  wide, and Enter (`.enter`) at most 900px.
- `.pagegrid` is an auto-fit grid of panels at `minmax(min(100%, 420px), 1fr)`: one column on phones and
  two or more on desktop. Inner grids also auto-fill: `.plots` 220px, `.res` 150px, `.troops` 140px,
  `.unit-inputs` 120px, `.worlds` 300px.
- One breakpoint, `@media (max-width: 640px)`: the hero stacks with 56px art, hero buttons stretch,
  the connect sheet docks to the bottom, and the tx log spans the width.
- Overflow: the nav scrolls sideways, tables sit in `.table-wrap` (`overflow-x: auto`), the map is a
  scrollable `.map-wrap` (max `min(70vh, 640px)`), and long values in `.kv dd` wrap anywhere.
- The connected-wallet button (`.acct-id`) stacks the village name over the short address. The name
  is ellipsized at 9em so the header fits narrow phones, and the full address is in `title`.

## Elevation & depth

The design is flat. Depth comes from the 3px `--frame` borders and tone (paper over straw, sunk rows).
The only shadows are the button's hard pixel frame (four 3px offset `box-shadow`s in `--wood-900`,
plus an inset 4px bottom shade). There is no blur anywhere. The only overlay is the connect sheet backdrop
`rgb(46 28 14 / 0.55)`. Stacking: tx log `z-index: 10`, skip link 20, sheet 30.

## Shapes

Every corner is square (`border-radius: 0` on buttons and inputs). Panels, cards, sheets and tx toasts
use a 3px `--frame` border, and inputs a 2px `--wood-700` border. Icons are pixel SVGs (`Pix` in `ui.tsx`)
rendered with `image-rendering: pixelated`.

## Components

- **Button** `.btn` + `.btn-primary | .btn-secondary | .btn-danger`, sized with `.btn-sm` (36px) or
  `.btn-lg` (52px), 44px by default. States: hover lightens, active moves down 2px (turned off by
  `prefers-reduced-motion`), `:focus-visible` gets a 2px `--focus` outline, and disabled is 60% opacity.
- **Act** (`web/src/tx.tsx`) is the only way to write on chain. It is a button that calls `send()`, shows
  "Working..." and `aria-busy` while its own write runs, and labels start with a verb ("Finish slot 1").
- **TxLog** (`tx.tsx`) is a fixed, `aria-live="polite"` list of writes. Each shows "Waiting for wallet",
  "Pending", "Confirmed" or "Reverted" with a plain-English note (errors in `web/src/errors.ts`,
  decoded against every game contract's errors) and an Etherscan link.
- **Panel** (`ui.tsx`) is a framed `section` with an `h2` title and optional `actions` on the right of
  its head.
- **Who** (`ui.tsx`) shows a player as **name** plus a short mono address linking to Etherscan, wherever a
  player appears. The wallet button, the Village title and the Map tile picker also pair name and
  `short()` address.
- **Countdown**, **Cost**, **Need** (empty state in `.empty`) and **Pix** are in `ui.tsx`.
- **ConnectSheet** (`web/src/wallet.tsx`) is one connect control: EIP-6963 wallets, Coinbase, and "Open in"
  wallet links on phones. It is a modal `role="dialog"` that closes with Escape.
- **Tabs** `.tab` / `.tab.on` with `aria-pressed` (Ranking). **Tables** in `.table-wrap`, with
  `td.r` for right-aligned numbers and `tr.me` for your own row.
- **Rows** `.plot`, `.slot`, `.tier`, `.reports li`, `.troops li` are sunk-tone list items inside panels.
- **Forms**: labels stack above 44px fields, `.hint` / `.hint.bad` sit beside the control they explain,
  and `.kv` is the definition-list layout for tile details.

## Do's and Don'ts

- Do start a new page as `<div className="pagegrid">` with `Panel`s. Use `Act` for every write and
  `Who` for every player.
- Do use role tokens (`--surface`, `--frame`, `--action`, `--danger`) rather than primitives or new hex values.
- Do keep to the six `--fs-*` sizes and the `--s-*` spacing steps.
- Do put directions next to their control (`.hint`) and give loading, error and empty states their own
  wording. Show "nothing yet" only after a successful read.
- Don't add rounded corners, blurred shadows, gradients or uppercase tracked labels.
- Don't show an address without its name, or a name without its short address.

Recipe: add a route in `web/src/App.tsx`, then build the page from `Panel` + `.kv`/row lists + `Act`
in `web/src/pages/`. Read through `read()` / `events()` in `web/src/chain.ts` and pass `GAME`
(Villages) as the namespace.

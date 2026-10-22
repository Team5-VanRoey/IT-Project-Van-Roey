# Design language

All colors and fonts live in `src/styles/theme.css`. Use these variables in CSS, never hard-coded hex values.

The brand colors and fonts come from the global styles of [vanroey.be](https://www.vanroey.be/). The app uses a dark theme whose surfaces are derived from VanRoey's slate text color.

## Brand

| Variable | Color | Use |
|---|---|---|
| `--color-primary` | `#287ABE` | Primary buttons, active menu item, hero background |
| `--color-primary-hover` | `#1F639B` | Hover state of primary elements |
| `--color-primary-dark` | `#0B2545` | Text and borders on top of the primary blue |
| `--color-primary-light` | `#F0F6FA` | Light backgrounds (light sections, print) |
| `--color-accent` | `#47D7AD` | Highlights, positive accents |
| `--color-slate` | `#47687F` | Logo wordmark color, secondary accents |
| `--color-text-brand` | `#384349` | Text on light backgrounds |
| `--color-grey` / `--color-grey-light` | `#C2C5C7` / `#ECEFF2` | Dividers and disabled states on light backgrounds |

## Dark UI

| Variable | Color | Use |
|---|---|---|
| `--surface-page` | `#1C2327` | Page background |
| `--surface-sidebar` | `#161C1F` | Sidebar |
| `--surface-raised` | `#252E33` | Cards, panels |
| `--border` | `#3A464D` | Borders and dividers |
| `--text-primary` | `#F0F6FA` | Main text |
| `--text-secondary` | `#C2C5C7` | Labels, helper text |

## Project status

Matches the steerco statuses (Good / Danger / Critical).

| Variable | Color | Status |
|---|---|---|
| `--status-green` | `#47D7AD` | Good |
| `--status-orange` | `#F5A524` | Danger |
| `--status-red` | `#E5484D` | Critical |

`--dev-yellow` (`#FFC400`) is only for development-only UI such as the DEV pill.

## Typography

- Headings (`h1`, `h2`): **Poppins** (`--font-heading`)
- Body text: **Open Sans** (`--font-body`)

Both fonts are installed as npm packages (`@fontsource`), so no external font service is needed.

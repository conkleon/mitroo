# Brand Immersion Refactor

Refactor all app screens to match the login screen's professional/military design language.

## Typography

- **Playfair Display**: screen titles, section headers, greeting text
- **Space Grotesk**: body text, buttons, labels, inputs, nav items, chips — replaces Inter everywhere
- **Letter-spacing**: +2.5-3 on "R.C.D." branding, +1.2 on section label overlines

## Color

- **Primary**: `#C62828` (red)
- **Gradient**: `#6B0000` → `#C62828` → `#D84315`
- **Surfaces**: White (screen bg, cards) — replaces `#F5F7FA`
- **Text**: `#1A1C1E` (primary), `#6B7280` (secondary), `#9CA3AF` (muted)
- **Borders**: `#E5E7EB` (cards/inputs), semi-transparent white (sidebar elements)

## Sidebar (Desktop)

- Dark red gradient background + `_CrossGridPainter` pattern
- White text/icons, semi-transparent glass effects on hover/selected
- Capsule chips for section labels, profile footer inverted to light-on-dark
- Selected item: white semi-transparent bg instead of red tint

## Screens (All)

- White backgrounds, Space Grotesk body font
- Playfair Display page titles
- Cards: white bg, `#E5E7EB` border, left red accent strip, 12-14px radius
- Section headers: 4px red vertical bar + bold text
- Stat cards: colored icon container + large value in Space Grotesk bold
- Chips: semi-transparent bg + matching thin border (login `_CapChip` pattern)
- Inputs: already close — ensure consistent 12px radius, red focus border

## Affected Files

1. `main.dart` — ThemeData: fonts, colors, card/appbar/input themes
2. `shell_screen.dart` — Dark gradient sidebar with painter
3. `dashboard_screen.dart` — Typography, stat cards
4. `services_screen.dart` — Cards, chips, tab bar, calendar
5. `departments_screen.dart` — Cards, chips
6. `items_screen.dart` — Cards
7. `item_detail_screen.dart` — Layout polish
8. `vehicles_screen.dart` — Cards
9. `vehicle_detail_screen.dart` — Layout polish
10. `service_detail_screen.dart` — Layout polish
11. `profile_screen.dart` — Layout polish
12. `admin_panel_screen.dart` — Layout polish
13. `forgot_password_screen.dart` — Match login form
14. `reset_password_screen.dart` — Match login form
15. All manage screens — Consistent card/chip/typography
16. Chat screens — Consistent typography, card styling

## What Stays

Layouts, component structure, data flow, route logic, business logic. No behavior changes.

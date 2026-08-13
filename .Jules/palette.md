## 2026-08-13 - Added missing ARIA label to Findings fix modal close button
**Learning:** The Guided fix modal's close button lacked an `aria-label` and explicit keyboard focus visibility.
**Action:** When adding close buttons to modals, ensure `aria-label="Close modal"` and Tailwind classes like `focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded` are included for accessibility.

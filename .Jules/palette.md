## 2024-08-09 - Accessible Icon Buttons
**Learning:** Icon-only buttons (like command copy or flash close) frequently lack `aria-label` attributes and explicit focus visible states (`focus-visible:ring-2`) in this repository.
**Action:** Always ensure icon-only buttons have an `aria-label` and `focus-visible` styles (`focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded`) applied when creating or modifying them.

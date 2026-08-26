## 2024-08-26 - Dynamic ARIA Labels in Loops
**Learning:** When adding ARIA labels to toggle buttons inside dynamically rendered loops (e.g., sidebar nav items in `layouts.ex`), the label must interpolate the unique item context (e.g., `aria-label={"Toggle #{item.label} menu"}`) instead of a static generic string. A static string like "Toggle menu" creates duplicate ambiguous announcements for screen readers.
**Action:** Always inspect the surrounding scope for loop variables when adding accessibility attributes to ensure they provide distinct context per item.

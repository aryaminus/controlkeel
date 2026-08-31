## 2024-08-31 - Dynamic ARIA labels in HEEx loops
**Learning:** When adding ARIA labels to elements within dynamically rendered loops in HEEx templates, static strings cause ambiguous or duplicate announcements for screen readers.
**Action:** Always interpolate unique context from the loop variable (e.g., `aria-label={"Toggle #{item.label} menu"}`) instead of using a static string.

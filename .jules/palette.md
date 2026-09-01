## 2026-09-01 - Adding ARIA labels to loop buttons in LiveView
**Learning:** When adding ARIA labels to buttons inside `nav_items()` or other dynamically rendered loops (e.g., in HEEx templates), statically defining `aria-label="Toggle menu"` results in duplicate ARIA labels that are ambiguous for screen readers.
**Action:** Always interpolate unique context from the loop variable (e.g., `aria-label={"Toggle #{item.label} menu"}`) instead of using a static string to prevent ambiguous/duplicate announcements for screen readers.

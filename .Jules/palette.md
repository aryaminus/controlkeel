## 2024-05-19 - Missing ARIA attributes on standalone icon action buttons
**Learning:** Icon-only action buttons (like the copy-to-clipboard button in `CommandPill`) often lack `aria-label` attributes and tooltips, which makes them inaccessible to screen readers and difficult for mouse users to understand.
**Action:** When adding or reviewing component-level action buttons with standalone icons, strictly verify that an appropriate `aria-label` and `title` (or tooltip) property is present so that all users receive adequate context.

## 2024-08-04 - Icon-only buttons lacking ARIA labels and focus states in utility components
**Learning:** Utility components like `CommandPill` frequently have icon-only buttons for copy-to-clipboard actions. These often lack `aria-label` attributes for screen readers and visible focus states (`focus-visible:ring-*`) for keyboard users.
**Action:** Always check icon-only buttons across all small utility/helper components to ensure they have an `aria-label` and `focus-visible` classes with an appropriate `rounded` style to make the focus ring look good.

## 2024-05-24 - Add ARIA Labels to Icon-Only Buttons
**Learning:** Icon-only buttons (like copy or close buttons) without ARIA labels are completely unreadable for screen readers, as they just announce them as "button". Adding `aria-label` provides the necessary context and improves accessibility for visually impaired users.
**Action:** Always verify if a button containing only an icon has an `aria-label`. Consider making `aria-label` mandatory in custom UI button components if they don't have text children.

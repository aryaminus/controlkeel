## 2026-08-23 - Consistent Keyboard Navigation
**Learning:** Custom interactive elements like sidebar buttons and specialized panel buttons often lack default focus states, making them inaccessible via keyboard. Relying on default browser outlines is insufficient when custom styles mask them.
**Action:** Always verify keyboard focus visibility for custom buttons and explicitly add Tailwind focus-visible classes like 'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary'.

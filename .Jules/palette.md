## 2025-02-14 - Standardize keyboard focus states
**Learning:** Found multiple icon-only close buttons lacking explicit keyboard focus outlines, leading to poor keyboard accessibility.
**Action:** Always add `focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded` to icon-only buttons to ensure they are visible to keyboard users.

---
name: User profile
description: Christopher Scott — BIP author working on post-quantum Bitcoin proposals
type: user
---

Christopher Scott (cmdruid) is the author of BIPs 368 and 369, working on post-quantum signature verification for Bitcoin Core.

- Deep understanding of Bitcoin consensus rules, Taproot internals, and soft-fork deployment
- Values clean separation of concerns (split BIP 368 from 369 when scope grew)
- Prefers simplicity over complexity (removed bare-key grace period/rate limiting in favor of outright ban)
- Wants specifications to stand alone (BIP enforcement rules should not reference other BIPs)
- Concerned about not confiscating user funds — but willing to disable bare-key spending when justified by security model
- Thinks in terms of "insurance policies" — the pre-activation SPHINCS+ tapleaf strategy
- Comfortable making architectural decisions quickly and iterating
- Prefers concrete implementation plans with file paths before coding
- Uses `dev/` directory for all project artifacts (docs, plans, reports, runbooks, memory)

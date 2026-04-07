---
name: Design feedback and preferences
description: Patterns learned from collaboration on BIPs 368/369
type: feedback
---

## BIP specification writing

- Each BIP's enforcement rules should stand alone without referencing other BIPs by number. Cross-references are fine for motivation/context but not in normative rule definitions.
**Why:** A BIP should be implementable from its own text. Referencing another BIP in enforcement logic creates a dependency that complicates review.
**How to apply:** In specification sections, describe the rule generically. Mention related BIPs in Design or Security Considerations.

- Prefer simplicity over complex exception handling. When bare-key grace periods and rate limiting were proposed, the user ultimately chose to ban bare-key spending outright.
**Why:** Complex exceptions undermine the security model they're trying to protect. Better to disable cleanly and allow future BIPs to add exceptions purpose-built.
**How to apply:** Default to the simplest rule that achieves the security goal. Only add exceptions when the user specifically requests them.

## Architecture

- Split distinct consensus changes into separate BIPs even if they're related. BIP 368 (key-path hardening) was split from BIP 369 (SPHINCS+ opcode) when key-path changes grew in scope.
**Why:** Cleaner review, independent activation, each BIP has focused scope.
**How to apply:** If a feature touches a different code path or could be activated independently, propose splitting.

- Follow existing Bitcoin Core patterns exactly. CLTV pattern for NOP redefinitions, buried deployment pattern for activation, existing test framework patterns for functional tests.
**Why:** Reduces review friction and ensures correctness by reusing battle-tested patterns.

## Implementation

- Use phased implementation: skeleton first (stub crypto), then tests, then real crypto, then integration tests. Each phase should build and pass tests independently.
**Why:** Catches integration issues early and allows progress verification at each step.

- The user prefers concrete plans with file paths and line numbers before coding starts. Use plan mode for anything non-trivial.

- DRY: when two BIPs share infrastructure (annex data storage), rename to generic names rather than duplicating or BIP-specific naming.

## Design preferences

- "Insurance policy" framing resonates: the user likes thinking about pre-activation SPHINCS+ tapleaves as quantum insurance that costs nothing until needed.
- No fund confiscation without strong justification. Bare-key ban was accepted because: BIP 341 recommends against it, wallets don't create them, BIP 9 provides migration time, and it can be reinstated.
- Parity bytes: derive rather than transmit when possible (CreateTapTweak returns parity, no need for extra annex byte).

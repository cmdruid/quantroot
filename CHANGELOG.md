# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Initial monorepo scaffold (Docker Compose, Makefile, docs structure)
- Bitcoin Core fork as submodule (`repos/bitcoin`, branch `quantroot`)
- Astro + Tailwind website scaffold (`services/website`)

### Bitcoin Core Fork (repos/bitcoin)

The `quantroot` branch implements the following on top of Bitcoin Core `master`:

#### BIP 369 — OP_CHECKSPHINCSVERIFY
- `OP_CHECKSPHINCSVERIFY` (`0xB3`) opcode handler in the script interpreter
- SPHINCS+ annex format: `0x50 || 0x04 || compact_size(N) || signatures`
- `SignatureHashSphincs` — BIP 342 sighash with `sha_annex` omitted
- Annex signature cursor with unconsumed-signature check
- Vendored `slhdsa-c` library with custom `slh_dsa_bitcoin` parameter set
- BIP 9 versionbits deployment with buried activation for regtest
- 43 functional tests (success, failure, hybrid, annex, cursor, codesep, activation)
- Benchmarks: `SphincsVerify` (~1.8 ms), `SphincsSign_Bench`
- 4 fuzz targets: verify, annex parse, keypath annex parse, tweak verify
- BIP specification, pseudocode, and test vectors

#### BIP 368 — Key-Path Hardening
- Internal key disclosure via annex type byte `0x02`
- NUMS point ban (BIP 341 `H` point)
- Bare-key spending disabled post-activation
- Tweak verification against output key
- 13 functional tests (annex, NUMS ban, tweak mismatch, activation)
- BIP specification, pseudocode, and test vectors

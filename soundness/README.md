# Cryptographic soundness whitepaper

LaTeX source for a focused whitepaper that traces the
authorisation-soundness claim of the simplest SEP-style policy
contract (`sep-anarchy`: any current member admits) down to four
base cryptographic assumptions, via a compositional reduction
across the BLS12-381 / KZG / Poseidon2 / Merkle / Fiat--Shamir /
PLONK stack.

The paper is intentionally short. It covers cryptographic
soundness only — no governance, no messaging-layer detail, no
deployment-specific economics.

## Build

```
make            # main.pdf
make clean
make distclean
```

Requires `latexmk` and a TeX distribution with `amsthm`,
`tikz`, `cleveref`, and `microtype` (e.g. TeX Live, MacTeX).

## Layout

```
soundness/
  main.tex          single-file source
  Makefile          latexmk entry points
  references.bib    self-contained bibliography
  README.md
  main.pdf          built artifact (checked in)
```

The paper is self-contained — `references.bib` carries every cited
entry, with no symlinks to the SoK or primitives bibliographies.

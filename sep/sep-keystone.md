## Preamble

```
SEP:        <to be assigned>
Title:      Anonymous Group-Membership Keystone (AGMK) — generic Soroban interface
Author:     <to be assigned>
Status:     Draft
Type:       Standard
Created:    2026-05-17
Updated:    2026-05-17
Version:    0.4.4
Discussion: <TBD>
Depends:    CAP-0059 (BLS12-381 host functions, activated in Protocol 22),
            CAP-0075 (Poseidon and Poseidon2 host functions, activated in Protocol 25)
```

## 1. Summary

This SEP specifies a Soroban contract interface for an *anonymous
group-membership keystone* (AGMK): a single on-chain contract that maintains,
per registered update relation, a Poseidon2-Merkle commitment to a set of
member leaves over the BLS12-381 scalar field, and advances that commitment
by verifying a PLONK proof that an authorised state transition has occurred.
The transition the proof attests to is fully encoded inside the per-relation
predicate (the verifying key) — admitting a new member, removing a member,
rotating a key, or any other $\mathcal{R}_{\text{Upd}}$-shaped relation fits
the same contract surface; the contract itself is neutral about which it
is. The SEP is normative for the **contract interface and the relation
contract** only; concrete predicates (anarchy, democracy, oligarchy,
removal, key-rotation, …) are out of scope and are deferred to follow-up
SEPs.

The cryptographic soundness statement that this contract operationalises is
established in the companion whitepaper *Cryptographic soundness of the
group-membership keystone* (hereafter, **the whitepaper**) and is not
repeated here in full. Two scope clarifications, surfaced here so that the
rest of the SEP can be read without ambiguity:

- **Scope asymmetry.** The whitepaper proves the soundness theorem for the
  *admission* predicate only. This SEP specifies a host contract that
  accepts any $\mathcal{R}_{\text{Upd}}$-shaped predicate. Every
  non-admission relation deployed under this SEP requires its own
  soundness argument under the same compositional chain (whitepaper §§3–7)
  before being relied on in production; the SEP itself does not extend the
  theorem to those relations.
- **Tag authenticity is out-of-band, by design.** Because
  `register_relation` is permissionless (§4.4, §5.5), the on-chain
  presence of a tag is *not* a trust attestation. Users MUST verify
  `(vk_digest, pi_schema_hash, bootstrap_root)` against artifacts
  published by the relation's author before relying on any tag, regardless
  of its human-readable name. The contract certifies nothing about
  intent; it is an interface, not a registry of canonical relations.
- **When AGMK is the right shape.** AGMK is the right pattern when a
  deployment expects to register relations *dynamically*: novel
  governance types, dynamic parameter choices (quorum thresholds, tier
  expansions), or third-party-published relations. For fixed-vk-set
  governance — where the entire $\mathsf{vk}$ family is decided at
  deploy time and never expected to grow without a redeploy — baking
  the verifying keys into the contract WASM at deployment is strictly
  simpler and cheaper than going through `register_relation`: no
  per-relation persistent-storage footprint per group, no
  $H_{\mathrm{bytes}}$ derivation at registration, no event payload
  carrying redundant $\mathsf{vk}$ bytes. The current
  `onym-contracts` family (`sep-anarchy`, `sep-tyranny`,
  `sep-oneonone`) is exactly this baked-vk pattern, and the AGMK SEP
  is not a strict improvement over it for those cases. The two
  patterns are complementary: bake when the $\mathsf{vk}$ set is
  fixed at deploy; use AGMK when the $\mathsf{vk}$ set is expected
  to grow on-chain after deploy.

## 2. Motivation

A growing class of on-chain protocols — anonymous messaging groups,
sybil-resistant DAOs, anonymous credentialing — needs a Soroban surface that
(a) maintains a privacy-preserving commitment to current membership, (b)
advances that commitment under an arbitrary, contract-agnostic update rule
(admission, removal, key rotation, or any other transition), and (c) does
so in constant proof size and constant verification cost. The common shape,
instantiated for every such rule, is identical modulo the *predicate* that
governs which transitions are valid:

1. an Fr-embedded commitment $C_g$ to the current member set,
2. a monotonic epoch $e$,
3. a per-relation domain tag $t$,
4. an update predicate $\mathcal{R}_{\text{Upd}}$ encoded as a PLONK circuit
   compiled to a verifying key $\mathsf{vk}$,
5. a contract that, on each step, verifies one PLONK proof and swaps
   $(C_g, e) \mapsto (C_g', e+1)$.

Multiple independent governance variants (anarchy, democracy, oligarchy,
…) and lifecycle relations (admission, removal, key rotation, …) share
this shape bit-for-bit beneath the keystone; only the predicate inside
$\mathcal{R}_{\text{Upd}}$, and therefore the verifying key, differs.
Specifying *one* generic Soroban contract that hosts all such predicates
via a relation tag is strictly less code, less audit surface, and less
operational complexity than specifying one contract per relation. The
contract itself takes no stance on what an update *means* — that meaning
lives entirely in the predicate.

## 3. Abstract

The AGMK contract is an **interface, not a canonical registry**: it
stores what registrants give it, verifies proofs against what it stores,
and certifies nothing about the meaning, authority, or provenance of any
tag. Trust in `(vk, bootstrap_root, pi_schema_hash)` is established
out-of-band by users who care about a tag — never by the contract.

The contract maintains a registry indexed by a `Symbol` tag. Each
registry entry pins, immutably after registration, a PLONK verifying key,
its SHA-256 digest, a hash of the public-input schema, and a bootstrap
Merkle root. The contract has no admin and no privileged operator:
registration of new relations is permissionless, and applying a step
under a registered relation is permissionless. It exposes one mutating
entry point — `apply(tag, new_root, expected_epoch, proof, extras)` —
that verifies a PLONK proof against the registered key under a fixed
five-element public-input vector

$$ \mathsf{pi} \;=\; (C_g,\; C_g',\; e,\; t_{\mathrm{Fr}},\; r_{\mathrm{ext}}) $$

and, on success, advances the on-chain state by exactly one epoch. The
extras vector is hashed by the contract to derive $r_{\mathrm{ext}}$, so
relation-specific public inputs of arbitrary arity reduce to a single
field element from the verifier's perspective. Tag-to-verifying-key
bindings are immutable; upgrades produce a new tag — making the
*version-locality* of the underlying soundness theorem (whitepaper §8)
explicit at the contract surface. Authenticity of any given tag is
established out of band by the users who care about it (by verifying
`vk_digest`, `bootstrap_root`, and `pi_schema_hash` against published
artifacts), not by the contract.

## 4. Specification

The language of this section is normative. Key words MUST, MUST NOT,
SHOULD, and MAY are to be interpreted as in RFC 2119.

### 4.1 Notation

| Symbol            | Meaning                                                                  |
|-------------------|--------------------------------------------------------------------------|
| $\mathbb{F}_r$    | the BLS12-381 scalar field                                               |
| $C_g \in \mathbb{F}_r$ | Poseidon2-Merkle root committing the current member set             |
| $C_g'$            | next-state root: the result of admitting one new member                  |
| $e \in \mathbb{N}$ | monotonic epoch counter, embedded into $\mathbb{F}_r$ as $e_{\mathrm{Fr}}$ |
| $t$               | relation tag, a Soroban `Symbol` (≤ 32 ASCII bytes by the SDK)           |
| $t_{\mathrm{Fr}}$ | Poseidon2 hash of $t$ under a fixed domain separator (see §4.7)          |
| $\mathsf{vk}$     | PLONK verifying-key blob                                                 |
| $\mathsf{vk}_d$   | SHA-256 digest of $\mathsf{vk}$                                          |
| $r_{\mathrm{ext}}$ | Poseidon2 hash of the extras vector under a fixed domain separator      |
| `EMPTY`           | sentinel $\mathbb{F}_r$ value, reserved by the deployment to mark empty leaf positions; each registered relation MUST forbid `EMPTY` as a member leaf |

### 4.2 Dependencies

This SEP relies on:

- **CAP-0059** — host functions for BLS12-381 ($\mathbb{G}_1$, $\mathbb{G}_2$, $\mathbb{F}_r$ arithmetic, hash-to-curve, multi-pairing). All $\mathbb{F}_r$ elements in this SEP are serialised as 32-byte big-endian integers per CAP-0059's canonical Fr encoding.
- **CAP-0075** — host functions for the Poseidon and Poseidon2 *permutations* over BLS12-381 $\mathbb{F}_r$.
- **SHA-256** — Soroban built-in (`env.crypto().sha256(...)`), used only for $\mathsf{vk}_d$.

The PLONK verifier is implemented in WASM against these host functions; it
is not itself a host function. The transcript discipline is fixed in §4.7.

#### 4.2.1 Canonical Poseidon2 sponge and hash helpers

CAP-0075 exposes the Poseidon and Poseidon2 *permutations* over
BLS12-381 $\mathbb{F}_r$, not a sponge construction. This section
pins the sponge mode used everywhere in this SEP and defines the two
hash helpers built on top of it. Conformance vectors are decidable
against this specification, not against CAP-0075 alone.

**Permutation parameters** (matching the whitepaper §2):

| Symbol | Value | Meaning |
|--------|-------|---------|
| $t$    | 3     | State width (number of $\mathbb{F}_r$ elements)            |
| $\alpha$ | 5   | S-box exponent                                             |
| $R_F$  | 8     | Full rounds                                                |
| $R_P$  | 56    | Partial rounds                                             |

Round constants and MDS matrix are the canonical Poseidon2 parameters
for $(\mathbb{F}_r, t = 3, \alpha = 5)$ derived per the Poseidon2
specification (Grassi–Khovratovich–Schofnegger, ePrint 2023/323) and
made available via the CAP-0075 host functions.

**Sponge construction.** Let $P : \mathbb{F}_r^3 \to \mathbb{F}_r^3$
denote the Poseidon2 permutation above. The sponge uses:

- **Rate $r = 2$, capacity $c = 1$** over the state width $t = 3$.
  State positions $s_0, s_1$ are the rate; $s_2$ is the capacity.
- **Initial state** $s = (0,\, 0,\, 0) \in \mathbb{F}_r^3$.
  Domain separation is carried by the `dom` argument absorbed as the
  first input element.
- **Absorption.** Given an input sequence $(x_0, x_1, \ldots, x_{m-1})$
  of $\mathbb{F}_r$ elements, process it in pairs. If $m$ is odd,
  conceptually append the zero element $0 \in \mathbb{F}_r$ to make
  it even (this is unambiguous because every helper below
  length-prefixes the input). For each pair $(x_{2i}, x_{2i+1})$:
    1. set $s_0 \leftarrow s_0 + x_{2i}$, $s_1 \leftarrow s_1 + x_{2i+1}$ (addition in $\mathbb{F}_r$);
    2. apply $s \leftarrow P(s)$.
- **Squeeze.** After the final absorbing permutation, return $s_0$ as
  the single output $\mathbb{F}_r$ element. Multi-element squeezes
  are not used in this SEP.

The sponge mode is pinned to $(r, c) = (2, 1)$ rather than $(1, 2)$
to match the rate/capacity split analysed for the $t = 3$ Poseidon
parameter family in the original Poseidon paper; implementations
MUST NOT alter the split.

**Byte-to-Fr hash, $H_{\mathrm{bytes}}(\text{dom}, \text{msg}) \to \mathbb{F}_r$.**
For a domain-separation Fr element $\text{dom}$ and an arbitrary-length
byte string $\text{msg}$:

1. Pack $\text{msg}$ into a sequence of $\mathbb{F}_r$ elements by
   31-byte chunks, big-endian. The final chunk MAY be shorter than 31
   bytes; right-zero-pad it to 31 bytes before big-endian
   interpretation. Call the resulting sequence
   $f_0, f_1, \ldots, f_{k-1}$.
2. Absorb the input vector
   $\bigl[\,\text{dom},\; \mathrm{len}_{\mathrm{Fr}}(\text{msg}),\; f_0,\, f_1,\, \ldots,\, f_{k-1}\,\bigr]$
   into the canonical sponge above, where
   $\mathrm{len}_{\mathrm{Fr}}(\text{msg})$ is the byte length of
   $\text{msg}$ embedded as an $\mathbb{F}_r$ element (the canonical
   $\mathbb{Z} \hookrightarrow \mathbb{F}_r$ embedding, since byte
   lengths fit trivially).
3. Squeeze a single $\mathbb{F}_r$ element and return it.

**Fr-vector hash, $H_{\mathrm{fr}}(\text{dom}, [a_0, \ldots, a_{n-1}]) \to \mathbb{F}_r$.**
For a domain-separation Fr element $\text{dom}$ and an Fr-element
vector of length $n$:

1. Absorb $\bigl[\,\text{dom},\; n,\; a_0,\, a_1,\, \ldots,\, a_{n-1}\,\bigr]$
   into the canonical sponge, with $n$ embedded as an
   $\mathbb{F}_r$ element.
2. Squeeze a single $\mathbb{F}_r$ element and return it.

The 31-byte chunk size in $H_{\mathrm{bytes}}$ is the largest that
guarantees each chunk encodes a valid $\mathbb{F}_r$ element
regardless of value (the Fr modulus is approximately $2^{255}$, so
$31 \cdot 8 = 248 < 255$ bits fits unconditionally). Implementations
MUST NOT use 32-byte chunks with modular reduction: that would
silently collide chunks whose high-bit interpretations differ by
multiples of $p$. The same prohibition applies to every byte→Fr
derivation in this SEP, including SHA-256 digests (see §4.7); no
byte string is ever reduced modulo $p$ as a raw embedding step.

The five domain-separation tags used elsewhere in this SEP are fixed
Fr elements derived once, by application of
$H_{\mathrm{bytes}}$ with the literal $\mathbf{0} \in \mathbb{F}_r$ as
the inner domain, from the ASCII byte strings:

| Constant             | ASCII source string         |
|----------------------|------------------------------|
| `TRANSCRIPT_TAG_FR`  | `"AGMK/v1/transcript"`       |
| `TAG_TAG_FR`         | `"AGMK/v1/tag"`              |
| `EXTRAS_TAG_FR`      | `"AGMK/v1/extras"`           |
| `SCHEMA_TAG_FR`      | `"AGMK/v1/pi-schema"`        |
| `VK_DIGEST_TAG_FR`   | `"AGMK/v1/vk-digest"`        |

That is, e.g.
$\texttt{TRANSCRIPT\_TAG\_FR} \;=\; H_{\mathrm{bytes}}(\mathbf{0}, \texttt{"AGMK/v1/transcript"})$.
These five strings are the only inputs to $H_{\mathrm{bytes}}$ that
use the literal zero domain; every other call uses one of these
constants.

### 4.3 Storage model

The contract uses three Soroban storage tiers, used as follows.

#### 4.3.1 Instance storage (singleton; small, cheap)

```rust
// Instance storage is unused in v1 of this SEP. The protocol_version
// view returns a hard-coded constant (see §4.4); no storage entry is
// required. Reserved for future SEP revisions that may need instance
// state.
```

The contract has no admin, no paused flag, and no initialiser. The
contract is operational as soon as its WASM is deployed.

#### 4.3.2 Persistent storage, per registered relation, keyed by `tag: Symbol`

```rust
enum PersistentKey {
    Relation(Symbol),       // RelationRecord
    State(Symbol),          // RelationState
}

#[contracttype]
struct RelationRecord {
    vk: Bytes,                  // PLONK verifying-key bytes
    vk_digest: BytesN<32>,      // SHA-256(vk)
    vk_digest_fr: BytesN<32>,   // H_bytes(VK_DIGEST_TAG_FR, vk_digest), computed once at register_relation
    pi_schema_hash: BytesN<32>, // Poseidon2 commitment to the extras schema; see §4.5
    extras_arity: u32,          // expected len() of the extras vector
    bootstrap_root: BytesN<32>, // initial C_g, immutable record
    registrant: Address,        // address that authorised this registration
    created_at_ledger: u32,
}

#[contracttype]
struct RelationState {
    current_root: BytesN<32>,   // C_g
    epoch: u64,
}
```

`RelationRecord` is written exactly once, by `register_relation`. It MUST
NOT be mutated by any subsequent call. `RelationState` is written by
`register_relation` (initially) and by each successful `apply` call.

#### 4.3.3 Temporary storage

Not used by this SEP. Implementations MAY use temporary storage internally
for proof-deserialisation scratch space but MUST NOT expose it.

### 4.4 Contract trait

```rust
/// Maximum size of the `extras` vector accepted by any registered
/// relation. Set normatively by this SEP to bound deserialisation cost
/// before predicate-specific arity validation; implementations MUST
/// reject `register_relation` calls with `extras_arity > MAX_EXTRAS_ARITY`
/// and `apply` calls with `extras.len() > MAX_EXTRAS_ARITY` before
/// reading the relation record.
///
/// 32 is chosen because 32 × 32 bytes = 1024 bytes is comfortably
/// above realistic governance-relation extras needs (typical
/// relations use 0–4 extras — for nullifiers, accumulator roots, or
/// auxiliary public keys) while sitting below the Soroban `Vec<BytesN<32>>`
/// deserialisation gas-cost knee.
const MAX_EXTRAS_ARITY: u32 = 32;

#[contract]
pub struct Keystone;

#[contractimpl]
impl Keystone {
    // ─── Registration ─────────────────────────────────────────────────────

    /// Authenticated by `registrant` but otherwise unrestricted: any
    /// account that authorises itself may register any tag. Registers
    /// a new relation under `tag` on behalf of `registrant`.
    ///
    /// After this call returns successfully, the registered tuple
    /// `(tag, vk_digest, vk_digest_fr, pi_schema_hash, extras_arity,
    /// bootstrap_root, registrant)` is immutable. There is no
    /// equivalent of `rotate_vk` and no privileged actor that can
    /// amend or evict a registration.
    ///
    /// Tag namespace is global and first-come-first-served. MUST call
    /// `registrant.require_auth()` before any state read or write, so
    /// the registrant address is verifiable from the transaction. MUST
    /// revert with `RelationAlreadyRegistered` if `tag` already exists.
    /// MUST revert with `MaxExtrasArityExceeded` if
    /// `extras_arity > MAX_EXTRAS_ARITY`. MUST revert with `InvalidVk`
    /// if `vk` does not parse as a PLONK verifying key over BLS12-381
    /// with the public-input arity 5 fixed by this SEP (see §4.6).
    /// MUST compute `vk_digest_fr = H_bytes(VK_DIGEST_TAG_FR, vk_digest)`
    /// per §4.2.1 and store it in `RelationRecord` before returning;
    /// the §4.7 transcript reads it from the record on every `apply`.
    pub fn register_relation(
        env: Env,
        registrant: Address,
        tag: Symbol,
        vk: Bytes,
        pi_schema_hash: BytesN<32>,
        extras_arity: u32,
        bootstrap_root: BytesN<32>,
    ) { /* … */ }

    // ─── Mutation ─────────────────────────────────────────────────────────

    /// Permissionless. Verifies one PLONK proof against the relation
    /// registered under `tag` and, on success, swaps
    /// `(current_root, epoch) → (new_root, epoch + 1)`.
    ///
    /// Reverts as documented in §4.6. Emits `applied` on success.
    /// As a side-effect, extends the TTL of `Relation(tag)` and
    /// `State(tag)` to the network maximum (§4.9).
    ///
    /// `apply` MUST NOT call `require_auth` on any address: the prover
    /// is anonymous, and the proof itself is the authorisation. MUST
    /// revert with `MaxExtrasArityExceeded` if
    /// `extras.len() > MAX_EXTRAS_ARITY` before reading the relation
    /// record.
    pub fn apply(
        env: Env,
        tag: Symbol,
        new_root: BytesN<32>,
        expected_epoch: u64,
        proof: Bytes,
        extras: Vec<BytesN<32>>,
    ) { /* … */ }

    // ─── Maintenance ──────────────────────────────────────────────────────

    /// Permissionless. Extends the TTL of `Relation(tag)` and
    /// `State(tag)` to the network maximum. Reverts with
    /// `RelationUnregistered` if `tag` is unknown. Emits `ttl_bumped`
    /// on success. Intended for relations that go quiet between
    /// `apply` calls; for active relations, `apply` does this
    /// implicitly.
    pub fn bump_ttl(env: Env, tag: Symbol) { /* … */ }

    // ─── Read-only views ──────────────────────────────────────────────────

    pub fn current_root(env: Env, tag: Symbol) -> BytesN<32> { /* … */ }
    pub fn current_epoch(env: Env, tag: Symbol) -> u64 { /* … */ }
    pub fn vk_digest(env: Env, tag: Symbol) -> BytesN<32> { /* … */ }
    pub fn vk_digest_fr(env: Env, tag: Symbol) -> BytesN<32> { /* … */ }
    pub fn bootstrap_root(env: Env, tag: Symbol) -> BytesN<32> { /* … */ }
    pub fn pi_schema_hash(env: Env, tag: Symbol) -> BytesN<32> { /* … */ }
    pub fn extras_arity(env: Env, tag: Symbol) -> u32 { /* … */ }
    pub fn registrant(env: Env, tag: Symbol) -> Address { /* … */ }
    pub fn is_registered(env: Env, tag: Symbol) -> bool { /* … */ }

    pub fn protocol_version(_env: Env) -> u32 { 1 }
}
```

The contract exposes three mutating methods (`register_relation`, `apply`,
`bump_ttl`) and **no privileged methods**. It is a pure verifier and
state machine. `register_relation` is gated only by self-authentication
of the `registrant` (so the registrant address is non-forgeable for
indexer use); it is otherwise unrestricted. `apply` and `bump_ttl`
require no authentication: `apply`'s authorisation is the proof itself,
and `bump_ttl` is a maintenance operation. Users verify
`(vk, bootstrap_root, pi_schema_hash)` out of band before trusting any
tag (§1, §6).

### 4.5 Registered relations: predicate requirements and schema commitment

#### 4.5.1 Minimum semantic shape of a registered predicate

The `register_relation` call accepts any verifying key with the fixed
five-element PI arity of §4.6; it cannot inspect what the predicate
constrains. The contract surface is therefore *trustworthy only to the
extent that the registered predicate satisfies the minimum semantic
shape below*. A vk that compiles and parses but whose constraint
system relates $C_g$ and $C_g'$ trivially produces a contract that
verifies arbitrary state transitions — fitting the PI shape is *not*
the same as fitting the soundness shape.

A predicate $\mathcal{R}_{\text{Upd}}$ registered under this SEP MUST:

1. Bind $C_g$ as the **sole authority on prior state**: every witness
   field the predicate consumes about the current member set MUST be
   either an opening of $C_g$ (via the Merkle scheme used for member
   leaves) or a deterministic function of such openings.
2. Constrain $C_g'$ as a **deterministic function of $C_g$ and the
   witness**: there MUST exist some publicly specified update function
   $U$ such that the predicate accepts iff
   $C_g' = U(C_g, w)$ for the supplied witness $w$. The function $U$
   MAY be partial (rejecting some witnesses) but MUST NOT be
   prover-chosen.
3. Bind $t_{\mathrm{Fr}}$ into its predicate body so that proofs for
   one relation cannot be re-used as proofs for another sharing the
   same vk shape (cross-relation domain separation).
4. SHOULD bind $e_{\mathrm{Fr}}$ either as a no-op input (for relations
   indifferent to the contract's epoch ordering) or as a constraint
   the predicate uses (for relations that need monotonicity).
5. MAY bind $r_{\mathrm{ext}}$ via per-relation interpretation of the
   extras vector; the contract treats $r_{\mathrm{ext}}$ opaquely.

A predicate that fails (1) or (2) produces a contract that *parses
correctly and verifies proofs* but that accepts state transitions the
soundness argument does not cover. The SEP cannot enforce (1)–(5)
in-contract; it states them normatively so that audit reviews,
conformance test suites, and out-of-band publisher claims have
a precise target to check.

#### 4.5.2 The `pi_schema_hash` commitment

A *public-input schema* is an ASCII-encoded, deployment-published string
that names, in order, the relation-specific fields packed into the
`extras` vector. For example, for a hypothetical key-rotation relation
whose extras carries the BLS12-381 G1 public key of the rotating
member:

```
extras_schema = "rotated_pk.x || rotated_pk.y"
```

The on-chain commitment is

$$ \mathsf{pi\_schema\_hash} \;=\; H_{\mathrm{bytes}}\bigl(\,\texttt{SCHEMA\_TAG\_FR},\;\mathrm{utf8}(\text{extras\_schema})\,\bigr) $$

where $\texttt{SCHEMA\_TAG\_FR}$ is the domain constant defined in §4.2.1.

The contract treats `pi_schema_hash` as an opaque commitment: it is stored,
returned by view functions, and absorbed into the Fiat–Shamir transcript
(§4.7), but is NOT interpreted otherwise. Schemas are documented out of
band; this SEP is silent on their content.

### 4.6 `apply` semantics

`apply(tag, new_root, expected_epoch, proof, extras)` MUST execute the
following steps, in order. The first failing step determines the revert
code.

1. **Bound check.** If `extras.len() > MAX_EXTRAS_ARITY`, revert with
   `MaxExtrasArityExceeded`. Performed before any storage read so that
   pathologically large inputs are rejected cheaply.
2. **Relation lookup.** Read `RelationRecord(tag)` and
   `RelationState(tag)` from persistent storage. If either is absent,
   revert with `RelationUnregistered`.
3. **Arity check.** If `extras.len() != record.extras_arity`, revert with
   `InvalidExtrasArity`.
4. **Epoch check.** If `expected_epoch != state.epoch`, revert with
   `EpochMismatch`.
5. **Extras digest.** Compute
   $r_{\mathrm{ext}} = H_{\mathrm{fr}}(\texttt{EXTRAS\_TAG\_FR},\; \texttt{extras})$
   per §4.2.1. For an empty extras vector,
   $r_{\mathrm{ext}} = H_{\mathrm{fr}}(\texttt{EXTRAS\_TAG\_FR},\; [\,])$.
6. **Tag digest.** Compute
   $t_{\mathrm{Fr}} = H_{\mathrm{bytes}}(\texttt{TAG\_TAG\_FR},\; \mathrm{utf8}(\texttt{tag}))$
   per §4.2.1.
7. **Public-input vector.** Set the five-element PI vector

   $$ \mathsf{pi} \;=\; (\,C_g,\; C_g',\; e_{\mathrm{Fr}},\; t_{\mathrm{Fr}},\; r_{\mathrm{ext}}\,) $$

   where $C_g$ is the prior `state.current_root`, $C_g'$ is `new_root`,
   $e_{\mathrm{Fr}}$ is the canonical $\mathbb{Z} \hookrightarrow
   \mathbb{F}_r$ embedding of the `u64` `state.epoch`,
   $t_{\mathrm{Fr}}$ is the tag digest from step 6, and
   $r_{\mathrm{ext}}$ is the extras digest from step 5.
8. **Verify.** Invoke `plonk_verify(record.vk, &proof, pi)` (§4.7). On
   failure, revert with `InvalidProof`.
9. **State update.** Write `state.current_root = new_root` and
   `state.epoch = state.epoch + 1`.
10. **TTL extension.** Extend the TTL of `Relation(tag)` and
    `State(tag)` to the network maximum (§4.9).
11. **Emit.** Emit `applied { tag, prev_root: C_g, new_root, new_epoch: state.epoch }`.

The contract performs **no** check that `new_root != state.current_root`
and **no** check that `new_root != 0`. Both would be the contract
imposing opinions about what counts as a legitimate predicate output;
the relation predicate is the sole authority on that (see §5.12).

The PLONK verifier MUST itself reject any proof whose serialised structure
deviates from the canonical layout fixed in §4.7. Implementations MAY
short-circuit malformed proofs before the pairing call, but MUST NOT
accept any proof that the canonical verifier would reject.

### 4.7 Fiat–Shamir transcript discipline

The verifier MUST absorb, in the listed order, the following 32-byte
big-endian Fr elements (per the CAP-0059 canonical serialisation
referenced in §4.2) before deriving any prover-message challenge:

| Slot | Content                                                |
|------|--------------------------------------------------------|
| 0    | $\texttt{TRANSCRIPT\_TAG\_FR}$ (the domain constant defined in §4.2.1) |
| 1    | `record.vk_digest_fr` — the precomputed Fr embedding of the relation's `vk_digest`, derived once at registration per §4.4; see §4.2.1 for the derivation rule |
| 2    | `record.pi_schema_hash`                                |
| 3    | $t_{\mathrm{Fr}}$                                      |
| 4    | $C_g$                                                  |
| 5    | $C_g'$                                                 |
| 6    | $e_{\mathrm{Fr}}$                                      |
| 7    | $r_{\mathrm{ext}}$                                     |

All eight slots are Fr elements serialised identically (32 bytes,
big-endian per CAP-0059); slot 0 is a constant per SEP version, and
slot 1 is constant per registered relation (read directly from the
immutable `RelationRecord`). Event payloads continue to expose the
raw `vk_digest` (32 bytes, SHA-256) for off-chain auditability,
alongside `vk_digest_fr` so indexers can verify the registrant's
derivation without recomputing it (§4.11).

No slot uses a direct 32-byte mod-$p$ embedding of a byte string;
every byte-input slot routes through $H_{\mathrm{bytes}}$. This
keeps the transcript consistent with §4.2.1's prohibition on
naive 32-byte-with-reduction packing and eliminates the
adversarially-controllable-vs-hash-derived inconsistency that
existed in v0.4.0.

Prover-message commitments and challenge derivations follow the PLONK
recipe of *PLONK: Permutations over Lagrange-bases for Oecumenical
Noninteractive arguments of Knowledge* (Gabizon, Williamson, Ciobotaru,
2019, ePrint 2019/953) under the simulation-extractable transcript
discipline analysed by Ganesh–Khoshakhlagh–Kohlweiss–Nitulescu–Zajac (SCN
2022, ePrint 2021/511). Any deviation from this absorption schedule —
including reordering, omission, alternate padding, or substitution of a
different domain string — voids the soundness statement of the whitepaper
(§§5–6 of the whitepaper) and produces a *different cryptosystem* that
MUST be analysed independently.

### 4.8 Replay protection

The contract provides replay protection at **one** layer; the second
layer is the responsibility of the registered relation's predicate.

#### 4.8.1 Proof-bytes replay (contract-enforced)

A successful `apply` advances `state.epoch` by exactly one. Every PLONK
proof binds — via the Fiat–Shamir transcript (§4.7) and the public-input
vector (§4.6 step 7) — to a specific
$(C_g, C_g', e, t_{\mathrm{Fr}}, r_{\mathrm{ext}})$. Resubmitting the
same proof bytes after a successful `apply` therefore fails:

- if the stale proof was bound to the old epoch, step 3 (`EpochMismatch`)
  rejects it cheaply, before the verifier runs;
- if the caller forges `expected_epoch` to match the new epoch but the
  proof still binds to the old, step 8 (`InvalidProof`) rejects it under
  the canonical transcript discipline.

The same proof under a *different* `tag` also fails, since
$t_{\mathrm{Fr}}$ is bound into the transcript.

#### 4.8.2 Witness-level replay (predicate-enforced)

A distinct question is whether the same witness opening (e.g. the same
member's Merkle leaf) may authorise *many* successive but distinct
`apply` calls. The answer is *predicate-specific*:

- For an **anarchy**-style relation, unlimited applies per member is the
  intended semantics; no witness-level non-replayability is required.
- For a **one-shot** relation (e.g. each member admits at most once),
  witness-level non-replayability MUST be encoded inside
  $\mathcal{R}_{\text{Upd}}$.

This SEP deliberately does NOT maintain a contract-level nullifier set
(see §5.10). The two recommended patterns are:

**(a) In-tree spent-slot.** The predicate proves that the witness leaf
is opened as `LIVE` in $C_g$ AND that the *same* slot is rewritten to a
`SPENT` variant in $C_g'$. Because $\mathcal{R}_{\text{Upd}}$ is a
single atomic step, the spent-state and the action-induced commitment
update are written together; a subsequent attempt to reuse the witness
opens `SPENT` in $C_g'$ and fails the `LIVE` check. This is the
preferred pattern: the membership commitment remains the sole authority
on which slots are live, and no contract-side bookkeeping is required.

The in-tree spent-slot pattern requires a **two-leaf-update**
predicate, which is structurally distinct from the single-leaf
admission predicate proved in the whitepaper. Concretely, the
predicate's witness carries:

- the admitter's index $\mathsf{idx}_a$, the admitter's `LIVE` leaf
  value $\ell_a$, and its sibling path $\mathsf{path}_a$ — opening
  $\ell_a$ at $\mathsf{idx}_a$ in $C_g$;
- the target index $\mathsf{idx}_e$, the new leaf value
  $\ell^{\star}$, and its sibling path $\mathsf{path}_e$ — opening
  `EMPTY` at $\mathsf{idx}_e$ in $C_g$ and writing $\ell^{\star}$ at
  $\mathsf{idx}_e$ in the intermediate root $C_g^{(1)}$;
- a second sibling-path opening of $\mathsf{idx}_a$ in $C_g^{(1)}$
  yielding $\ell_a$ — required because the path digest at
  $\mathsf{idx}_a$ may have changed between $C_g$ and $C_g^{(1)}$
  along shared internal nodes;
- the final commitment $C_g' = $ rewrite of $\mathsf{idx}_a$ from
  $\ell_a$ to its `SPENT` variant in $C_g^{(1)}$.

The predicate constraints MUST therefore include: (i) two Merkle
verifications against $C_g$, (ii) two Merkle recomputations (the
admitter-spend and the new-member-write), (iii) **two-witness
compatibility**, defined precisely as follows.

For two distinct leaf positions $\mathsf{idx}_a$ and $\mathsf{idx}_e$
in a Merkle tree of depth $D$, let $h_{\mathrm{LCA}} \in \{1, \ldots, D\}$
denote the height of their lowest common ancestor — i.e., the
smallest positive integer such that
$\lfloor \mathsf{idx}_a / 2^{h_{\mathrm{LCA}}} \rfloor = \lfloor \mathsf{idx}_e / 2^{h_{\mathrm{LCA}}} \rfloor$.
Index sibling paths from the leaf level (level 0) up to the level
immediately below the root (level $D - 1$). The compatibility
constraint is:

$$ \mathsf{path}_a[\ell] \;=\; \mathsf{path}_e[\ell] \qquad \text{for every } \ell \text{ with } h_{\mathrm{LCA}} \;\le\; \ell \;\le\; D - 1. $$

The three regions of $\ell \in \{0, \ldots, D - 1\}$ are:

- **Independent**, $0 \le \ell \le h_{\mathrm{LCA}} - 2$: the two
  leaves descend through disjoint subtrees at these levels; their
  siblings share nothing. (Empty when $h_{\mathrm{LCA}} = 1$.)
- **Cross-related**, $\ell = h_{\mathrm{LCA}} - 1$: at this level,
  $\mathsf{path}_a[h_{\mathrm{LCA}} - 1]$ is $\mathsf{idx}_e$'s
  ancestor at level $h_{\mathrm{LCA}} - 1$ — i.e., the other child
  of the LCA — and $\mathsf{path}_e[h_{\mathrm{LCA}} - 1]$ is
  $\mathsf{idx}_a$'s ancestor at the same level. These are NOT in
  general equal; they are the recomputed sibling values the
  predicate uses to compose the two-leaf update at the LCA boundary.
- **Equal**, $h_{\mathrm{LCA}} \le \ell \le D - 1$: at and above the
  LCA the two leaves share ancestors, hence siblings;
  $\mathsf{path}_a[\ell]$ and $\mathsf{path}_e[\ell]$ MUST be
  bit-identical. (Empty when $h_{\mathrm{LCA}} = D$.)

For example, with $D = 4$, $\mathsf{idx}_a = 5$, $\mathsf{idx}_e = 6$:
the LCA is at height $2$ (both leaves share
$\lfloor \mathsf{idx} / 4 \rfloor = 1$), so $h_{\mathrm{LCA}} = 2$.
Level $0$ is independent (siblings are leaves $4$ and $7$, in
disjoint subtrees); level $1$ is cross-related
($\mathsf{path}_a[1]$ is the level-$1$ node containing
$\mathsf{idx}_e$, $\mathsf{path}_e[1]$ is the level-$1$ node
containing $\mathsf{idx}_a$); levels $2$ and $3$ are equal (the
LCA's sibling at level $2$ and the root's sibling-side child at
level $3$ appear identically in both paths).

Implementations that omit the equality constraints in the
equal-region levels are unsound: they allow the prover to "see"
two inconsistent versions of $C_g$ and produce a $C_g'$ that does
not correspond to any single witness opening of the prior state.

`SPENT` is a per-relation sentinel distinct from `EMPTY`; the relation
predicate is responsible for fixing its value (e.g.,
$\texttt{SPENT}(\ell) = \mathrm{Poseidon2}(\ell,\, \texttt{SPENT\_TAG\_FR})$)
and for ensuring every `LIVE` check explicitly rejects both `EMPTY`
and `SPENT`. The SEP does not normatively name `SPENT` because, like
`EMPTY`, it is a relation-deployment concern; but every spent-slot
predicate MUST publish its `SPENT` construction alongside its
`extras_schema`.

The whitepaper's Theorem 1 covers only the single-leaf admission
case; soundness for any two-leaf-update relation must be
re-established under the same compositional chain, with an additional
reduction step covering the two-witness compatibility constraint.

**(b) External accumulator.** The predicate maintains a separate
nullifier-accumulator root in one of the `extras` field elements;
$\mathcal{R}_{\text{Upd}}$ proves "new accumulator root = insert(old
accumulator root, nullifier(witness))" alongside its other constraints,
and the relation's circuit reads the prior accumulator root from a
slot of $C_g$ (e.g., a reserved leaf position). Because the
accumulator root lives inside the committed state, it inherits the
membership-tree's TTL and archival guarantees automatically.

In either case, the contract treats the nullifier semantics opaquely:
all it sees is a $C_g \to C_g'$ transition under a fixed verifier and a
fixed Fiat–Shamir transcript.

### 4.9 Storage TTL strategy

Soroban Persistent storage entries expire when their TTL elapses; once
expired, entries are *archived*, not deleted, and become inaccessible
until restored via a `restoreFootprint` operation. An archived
`Relation(tag)` or `State(tag)` therefore blocks every subsequent
`apply` under that tag until restoration. The contract MUST manage TTLs
to make this rare and recoverable.

| Storage entry                | Tier        | TTL policy                                                                 |
|------------------------------|-------------|----------------------------------------------------------------------------|
| `ProtocolVersion` (instance) | Instance    | Implicit. Bumped by the platform on any invocation.                        |
| `Relation(tag)`              | Persistent  | Set to network max at registration. Extended to network max on every successful `apply` and every `bump_ttl(tag)` call. |
| `State(tag)`                 | Persistent  | Set to network max at registration. Extended on every successful `apply` and `bump_ttl(tag)`. |

The contract MUST extend both `Relation(tag)` and `State(tag)`
**unconditionally** to the network-configured maximum on every
successful `apply` and `bump_ttl` call. The SDK idiom is
`extend_ttl(network_max - 1, network_max)`: the threshold is set one
ledger below the maximum so the comparison is always true and the
extension always fires. Implementations MUST NOT use a smaller
threshold; conformance vectors check that the TTL after an `apply`
matches the network maximum exactly, not "at least some fraction of
the maximum".

The marginal cost of one `extend_ttl` host call per entry per `apply`
is negligible against the PLONK pairing call, so amortising the
extension across calls (e.g., bumping only every N applies) buys
nothing and creates a conformance discrepancy that auditors would
have to track.

A permissionless `bump_ttl(tag)` method (§4.4) exists for relations
that go quiet for long enough that no `apply` fires inside one TTL
period. Anyone may call it; the caller pays gas. `bump_ttl` MUST emit
a `ttl_bumped { tag, new_ttl_ledger }` event so indexers tracking
quiet relations can correlate without polling Soroban-RPC for ledger
entries.

If `Relation(tag)` or `State(tag)` does archive, the SDK error surfaces
as a transaction-level failure that the calling client MUST resolve by
including a `restoreFootprint` operation. The contract does not provide
an in-contract restore method; restoration is a chain-level concern.

### 4.10 Immutability of registered relations

After `register_relation(tag, ...)` succeeds, the tuple
`(tag, vk_digest, pi_schema_hash, extras_arity, bootstrap_root)` MUST NOT
be mutated by any contract method. There is no `rotate_vk` method, no
`update_vk` method, and no admin override.

To upgrade a relation, the deployment MUST register a NEW tag (typically
suffixed with a version, e.g. `sep_anarchy_v2`) and migrate state out of
band — for example, by passing the prior relation's final
`current_root` as the new relation's `bootstrap_root`. This makes the
*version-locality* of the soundness theorem (whitepaper §8) explicit at
the contract surface: admissions accepted under the old tag remain bound
to the old `vk`, and admissions under the new tag are bound to the new
`vk`; there is no in-place ambiguity.

### 4.11 Events

All events are emitted with the contract address as the first topic and
the listed `Symbol` literal as the second topic.

| Symbol               | Data                                                                                      | When emitted                          |
|----------------------|-------------------------------------------------------------------------------------------|---------------------------------------|
| `applied`            | `(tag: Symbol, prev_root: BytesN<32>, new_root: BytesN<32>, new_epoch: u64)`              | successful `apply`                    |
| `relation_registered`| `(tag: Symbol, registrant: Address, vk_digest: BytesN<32>, vk_digest_fr: BytesN<32>, pi_schema_hash: BytesN<32>, bootstrap_root: BytesN<32>, extras_arity: u32)` | successful `register_relation` |
| `ttl_bumped`         | `(tag: Symbol, new_ttl_ledger: u32)`                                                      | successful `bump_ttl`                 |

`relation_registered` carries the `registrant` address so indexers can
attribute tags to publishers and filter known squatter addresses;
`applied` deliberately omits any caller identifier because the prover
is anonymous (§5.5).

### 4.12 Errors

Implementations MUST surface errors as Soroban contract errors (`Error`
enum) with the following codes:

| Code | Symbol                       | Meaning                                                    |
|------|------------------------------|------------------------------------------------------------|
| 1    | `RelationUnregistered`       | unknown `tag`                                              |
| 2    | `RelationAlreadyRegistered`  | `register_relation` for an existing `tag`                  |
| 3    | `MaxExtrasArityExceeded`     | `extras.len() > MAX_EXTRAS_ARITY` (in `apply`) or `extras_arity > MAX_EXTRAS_ARITY` (in `register_relation`) |
| 4    | `InvalidExtrasArity`         | `extras.len() != record.extras_arity`                      |
| 5    | `EpochMismatch`              | `expected_epoch != state.epoch`                            |
| 6    | `InvalidProof`               | `plonk_verify` returned false                              |
| 7    | `InvalidVk`                  | `vk` failed to parse during `register_relation`            |

## 5. Design rationale

### 5.1 Why one contract with a relation registry?

The whitepaper's soundness theorem is parametric in $\mathcal{R}_{\text{Upd}}$:
the same compositional chain establishes authorisation soundness for every
predicate that fits the
$(C_g, C_g', e, t)$-public-input, $\mathcal{R}_{\text{Upd}}$-shape.
Multiple proposed governance variants and lifecycle relations share that
shape today, and ongoing work is expected to add more. A single contract
that dispatches by `tag` keeps the deployment, audit, and indexer surface
small (one ABI, one address, one event stream) and forces every relation
into the same Fiat–Shamir discipline. Deploying one contract per relation
would multiply audit surface without adding any cryptographic structure.

### 5.2 Why is `(tag, vk)` immutable after registration?

The whitepaper §8 states explicitly that the soundness theorem assumes
stable verifier semantics and verifying-key selection over the lifetime of
the deployment; an upgrade produces a *fresh instantiation* whose
soundness must be re-established for the new artifacts. The cleanest
on-chain expression of that is to disallow in-place `vk` rotation. A
`rotate_vk` method would create a window in which proofs valid under one
$\mathsf{vk}$ are replayable, or accepted, under a different
$\mathsf{vk}$ — exactly the kind of cross-version ambiguity the
soundness theorem rules out.

Operationally, "upgrade" becomes "register a new tag with the prior
relation's final root as its bootstrap". This is more verbose but unifies
the upgrade story with the deployment story.

### 5.3 Why a fixed five-element PI vector?

PLONK preprocessing is parametric in the *number* of public inputs.
Fixing the count to five lets one verifier implementation serve every
registered relation; the only artefact that varies per relation is the
verifying key. Per-relation public inputs of higher arity are folded into
$r_{\mathrm{ext}}$, a single field element, via Poseidon2 — at the cost
of one extra constraint inside each per-relation circuit to recompute and
bind that hash, which is negligible.

### 5.4 Why `expected_epoch` as an explicit argument?

The epoch is already a public input bound to the proof, so a stale proof
would fail at step 8 (`InvalidProof`) regardless. The explicit
`expected_epoch` argument lets callers fail at step 4 — *before* the
expensive PLONK verification — which makes race conditions cheap to
detect and recover from. It also makes the prover's intent explicit in
the transaction payload, which is useful for indexers.

### 5.5 Why permissionless `apply` (and why no admin)?

The whole point of the keystone is that *the proof itself* is the
authorisation. A participant's right to apply a transition is
established by the witness inside the predicate, not by the Stellar
account that submits the transaction. Gating `apply` on `require_auth`
of any specific address would re-introduce a non-anonymous identity
into the transition path. Spam and DoS are metered by Stellar gas: an
attacker pays for each invalid proof they submit, and the verifier
rejects them.

Registration is permissionless for the same reason. An admin who
registers `(tag, vk, bootstrap_root)` certifies *nothing* the user could
not certify themselves: the user MUST verify `vk_digest`,
`pi_schema_hash`, and `bootstrap_root` against published artifacts
before trusting any tag. Having an on-chain admin therefore adds a
trust-amplifying actor (a key that can introduce additional tags) but
removes no out-of-band verification burden. Eliminating the admin
strictly reduces the attack surface: there is no key whose compromise
allows an attacker to inject malicious tags or pause the contract.

The cost is that the tag namespace is global and first-come-first-served:
griefers can squat human-readable tags. This is a UX problem, not a
cryptographic one, and is discussed in §6.

### 5.6 Why no `remove_member` / `revoke` method?

Removal is not a separate method — it is a separate *relation*. A
removal relation's $\mathcal{R}_{\text{Upd}}$ predicate writes `EMPTY`
back to a target position and proves that whoever is authorised to
remove members (a quorum, an admin leaf, the position's owner, …) has
consented. From the contract's point of view this is just another
registered tag with its own $\mathsf{vk}$; the `apply` entry point is
already neutral about whether the transition adds, removes, or
otherwise mutates the committed set.

**Soundness coverage.** The whitepaper's Theorem 1 is proved only for
the admission predicate $\mathcal{R}_{\text{Upd}}^{\text{admit}}$
defined in whitepaper §4. The SEP's host accepts any predicate fitting
the $(C_g, C_g', e, t, r_{\mathrm{ext}})$ five-element-PI shape, but
*the theorem does not extend automatically*. A removal, key-rotation,
or other lifecycle relation must be analysed independently — typically
by re-running the whitepaper's §§5–7 chain against the new predicate
and re-establishing the win-condition contradiction for that
predicate's misuse model. Deployments MUST publish a soundness
argument (or cite an existing one) alongside any non-admission tag
they register; the SEP cannot enforce this, but the conformance
recommendation in §8 calls for it.

### 5.7 Why bind `pi_schema_hash` into the transcript?

Two relations that share a $\mathsf{vk}_d$ but diverge in their extras
schema are *different cryptosystems* — the prover and verifier disagree
on what $r_{\mathrm{ext}}$ binds. Absorbing `pi_schema_hash` into the
Fiat–Shamir transcript forces both sides to commit to the same schema and
makes any divergence an unforgeable transcript mismatch.

### 5.8 Why is `EMPTY` not exposed as a contract constant?

`EMPTY` is a per-deployment $\mathbb{F}_r$ value chosen at deployment
time; the contract does not need it to do its job (it never constructs a
leaf), and exposing it as a contract constant would falsely suggest the
contract enforces it. The relation circuits MUST forbid `EMPTY` as a
member leaf; the contract MUST NOT.

### 5.9 Why `Symbol` for `tag` rather than `BytesN<32>`?

`Symbol` is bounded to short ASCII strings, well-indexed by Stellar
infrastructure, and human-readable in events and logs. The Fr-embedded
$t_{\mathrm{Fr}}$ is derived deterministically inside `apply` (§4.6
step 6); the on-chain `Symbol` is the *handle*, not the predicate
identifier consumed by the circuit. A 32-byte hash on the surface would
serve the latter role better but the former worse, and the latter is
already covered by $t_{\mathrm{Fr}}$.

### 5.10 Why no contract-level nullifier set?

Two reasons (developed in §4.8).

First, Soroban's archival semantics make a contract-stored nullifier
set unsound under operational drift. A nullifier entry that exceeds its
TTL is *archived*: reads by the contract return absent, the contract
concludes the nullifier was never seen, and a duplicate witness is
accepted. There is no atomic "is this entry archived?" check available
to the contract, and per-nullifier TTL bumping is fragile (the next
`apply` does not know which nullifiers exist for the relation; an
indexer-driven bumper introduces a centralisation surface). A
Merkle-accumulator variant (one entry per relation, easy to bump)
recovers correctness but pushes substantial circuit complexity into
every relation that uses it.

Second, the natural place for witness-level non-replayability in a
membership-commitment system is *inside the membership commitment
itself*: rewrite the spent slot to a sentinel variant as part of the
$\mathcal{R}_{\text{Upd}}$ step (the in-tree spent-slot pattern of
§4.8.2(a)). This makes the membership tree the sole authority on which
slots are live, eliminates a side channel, and inherits the membership
tree's TTL story automatically. Relations for which in-tree marking is
unnatural can carry their own accumulator inside an `extras` field
without involving the contract.

Pushing nullifier semantics into the predicate also keeps the contract
neutral: the same `apply` entry point serves admission, removal,
key-rotation, and one-shot variants without any of them privileged at
the storage layer.

### 5.11 Why no `RootUnchanged` or `EmptyNewRoot` check?

Earlier drafts had `apply` reject `new_root == state.current_root`
and `new_root == 0` pre-verifier. Both checks were removed.

`RootUnchanged` would have prevented a predicate from accepting a
no-op-on-root transition that nonetheless advances the epoch — for
example, a liveness-tick or commit-only relation whose
$\mathcal{R}_{\text{Upd}}$ leaves the membership commitment fixed but
advances $e$ to record a heartbeat or to bind a nullifier-accumulator
update in `extras`. The contract has no way to distinguish such a
legitimate predicate output from a buggy one without reading the
predicate, which it cannot do. Per §4.5.1, the predicate is the sole
authority on what counts as a valid transition; the contract is
neutral.

`EmptyNewRoot` would have rejected `new_root == 0` as a defence
against client zero-initialisation bugs. The protection is real but
narrow: an all-zero `new_root` is just as cryptographically
improbable as any other specific Fr element from a sound predicate
($\Pr \le 2^{-255}$), so the check defends only against client bugs,
not against predicate misbehaviour. Symmetry with
`register_relation`'s acceptance of `bootstrap_root == 0` made the
asymmetry awkward; rather than add a matching `EmptyBootstrapRoot`
check to `register_relation`, both checks were removed. Client-bug
defence belongs in the SDK or in the calling client, not in the
contract surface.

The neutrality principle: the contract verifies proofs and advances
state; it does not curate the *shape* of legitimate state
transitions. That curation is the predicate's job, and §4.5.1 states
the minimum semantic requirements normatively.

### 5.12 Why not promote `pi_schema_hash` to a sixth public input?

An earlier reviewer suggested adding `pi_schema_hash` to the PI
vector — making it 6-element rather than 5 — on the grounds that a
verifier implementation could mis-absorb it into the transcript while
the PI vector still looked correct, and a 6th PI would catch that
class of bug.

The argument addresses a real bug class but is asymmetric in its
defence. A verifier that mis-absorbs `pi_schema_hash` and a verifier
that mis-absorbs `vk_digest`, $C_g$, $C_g'$, $e_{\mathrm{Fr}}$, or
$r_{\mathrm{ext}}$ all produce equally invisible soundness gaps; a
6-PI design defends against only the first. The correct defence for
the whole class is *comprehensive transcript-discipline conformance
vectors*, which §8 requires (one proof per absorption-order
permutation; all but the canonical order must revert `InvalidProof`).
Hardening the conformance harness covers every variant; adding one
field to the PI vector covers one.

Promoting `pi_schema_hash` to a PI would also change the verifier's
preprocessing-polynomial degree across every relation registered
under this SEP and add one constraint to every circuit, in exchange
for asymmetric coverage. The five-element design is therefore kept;
the bug class is addressed at the conformance layer.

### 5.13 Why `require_auth(registrant)` on `register_relation`?

Registration is permissionless in the sense that there is no admin
gate — any account may register any tag — but it is not anonymous.
The contract calls `registrant.require_auth()` so the registrant
address bound into the `RelationRecord` and emitted in
`relation_registered` is non-forgeable. This costs nothing in
trust-minimisation (the admin-key compromise risk does not exist —
there is no admin) and gains indexers a robust attribution channel:
publisher-prefix tag conventions are forgeable, but `registrant` is
not. Tag-squatting mitigations in §6 lean on this distinction.

`apply` deliberately does NOT call `require_auth`: the prover is
anonymous, and the proof is the authorisation. Binding the submitter
address into the admission path would re-introduce a non-anonymous
identity that the privacy model rules out.

### 5.14 Why extend TTL to network maximum on every apply?

`State(tag)` is updated by every `apply`; without explicit extension
its TTL would creep upward only marginally each call (depending on
SDK defaults), and an active relation could still archive if usage
clusters and then pauses. Extending to the configured maximum every
time turns TTL management from an operational concern into a
free-rider concern: any caller paying gas for an `apply` keeps the
relation alive for the full archival horizon. The marginal cost is one
`extend_ttl` host call per write, which is small relative to the
PLONK pairing call.

`Relation(tag)` is *never* written after registration, so its TTL
would otherwise erode monotonically. Bumping it alongside `State(tag)`
on every `apply` ties the two together and prevents an asymmetry where
the mutable state is alive but the verifying key is archived (which
would block `apply` until restoration).

## 6. Security concerns

The cryptographic-soundness statement (whitepaper Theorem 1) is the
guarantee this SEP operationalises. Below is a non-exhaustive list of
deployment-side risks that lie outside the scope of the theorem and that
the SEP cannot itself address:

- **Verifying-key supply chain.** The on-chain `vk` MUST be the canonical
  one produced by deterministic preprocessing of the relation's published
  circuit source. Disciplines (a)–(d) of whitepaper §8 apply unchanged.
- **Bootstrap root authenticity.** The genesis `bootstrap_root` for each
  relation is set by whoever registers the tag. A maliciously-chosen
  bootstrap voids every subsequent step's soundness statement.
  Deployments MUST publish the construction of every bootstrap root
  alongside the SEP-conformant ABI; users MUST verify the published
  bootstrap root against the on-chain `bootstrap_root(tag)` view before
  trusting any tag.
- **Tag squatting.** Because registration is permissionless and the tag
  namespace is global FCFS, an attacker can register a human-readable
  tag (e.g. `sep_anarchy`) with a vk/bootstrap of their choosing before
  the canonical deployment. Mitigations: (i) deployments SHOULD use
  namespaced tags that include a publisher prefix and version (e.g.
  `onym_sep_anarchy_v1`), and (ii) users MUST verify
  `(vk_digest, pi_schema_hash, bootstrap_root)` against published
  artifacts before trusting any tag, regardless of its human-readable
  name. The contract certifies *nothing* about a tag beyond what was
  registered under it.
- **Chain reorganisation.** Sequential composition (whitepaper §4) is
  conditional on the chain providing a total ordering of transactions.
  Chain-level reorgs are out of scope.
- **Upgrade boundary.** Soundness across an upgrade (new tag with
  migrated root) MUST be re-established for the new $\mathsf{vk}$ under
  the same compositional argument. The contract does not enforce any
  cryptographic relationship between an old and a new tag.
- **Denial of service.** Both `apply` and `register_relation` are
  permissionless. An attacker can submit unbounded invalid proofs or
  unbounded junk registrations at their own gas cost. The contract
  does not rate-limit; Stellar gas is the metering layer. Indexers
  SHOULD filter the `relation_registered` event stream by
  publisher-prefix conventions to suppress squatting noise.
- **Front-running of proofs.** Because proofs are anonymous, a proof
  valid under epoch $e$ is replayable until the epoch advances. Honest
  provers SHOULD submit proofs through MEV-aware channels (e.g.,
  private mempools, encrypted submission) when the relation's privacy
  model warrants it.
- **Witness-level replay (predicate responsibility).** The contract
  enforces proof-bytes non-replayability (§4.8.1). Witness-level
  non-replayability — whether the same Merkle opening may authorise
  multiple successive distinct applies — is determined entirely by the
  relation predicate. Relations that require one-shot semantics MUST
  encode them inside $\mathcal{R}_{\text{Upd}}$ following one of the
  patterns of §4.8.2. A predicate that does not encode the intended
  one-shot constraint produces a contract that *appears to verify
  correctly* while admitting unlimited replays of the same witness.
- **State archival.** Persistent storage entries that exceed their TTL
  are *archived* and become inaccessible until explicitly restored.
  An archived `Relation(tag)` or `State(tag)` blocks every subsequent
  `apply` under that tag until a `restoreFootprint` operation is
  included. The contract bumps both entries to network-max TTL on
  every successful `apply` (§4.9) and exposes a permissionless
  `bump_ttl(tag)` for quiet relations, but does not provide an
  in-contract restoration path. Deployments SHOULD monitor TTLs
  off-chain (Soroban-RPC `getLedgerEntries` exposes them) and trigger
  `bump_ttl` before the archival window expires.

## 7. Backwards compatibility

This SEP defines a new contract interface. It does not modify, extend, or
deprecate any existing Stellar or Soroban interface. It depends on
CAP-0059 (Protocol 22+) and CAP-0075 (Protocol 25+).

## 8. Reference implementation

To be linked from the final SEP. Implementations MUST pass the conformance
vector set published alongside this SEP, which exercises (at minimum):

- `register_relation` happy path: `relation_registered` event includes
  `registrant`, and the registrant's `require_auth` is verified by the
  transaction signing harness;
- `register_relation` immutability, **including cross-caller**: account A
  registers tag `foo`; account B (different address, fresh signature) tries
  to register `foo` with different `(vk, bootstrap_root)`; the second call
  MUST revert `RelationAlreadyRegistered`. The first call's
  `(registrant, vk_digest, bootstrap_root)` MUST remain unchanged in
  storage and view-function output;
- `register_relation` bound check: `extras_arity > MAX_EXTRAS_ARITY` MUST
  revert `MaxExtrasArityExceeded` before any storage write;
- **`vk_digest_fr` derivation at registration.** A `register_relation`
  call MUST produce a `RelationRecord` whose `vk_digest_fr` field
  equals `H_bytes(VK_DIGEST_TAG_FR, vk_digest)` per §4.2.1, and the
  `relation_registered` event payload MUST include the same value.
  A harness that recomputes `vk_digest_fr` from the event's
  `vk_digest` and finds a mismatch MUST fail conformance;
- `apply` happy path, including event emission, state advancement, and
  TTL extension of both `Relation(tag)` and `State(tag)` to *exactly* the
  network maximum (the conformance harness reads ledger-entry TTLs before
  and after; thresholds below the maximum are a conformance failure per
  §4.9);
- `apply` bound check: `extras.len() > MAX_EXTRAS_ARITY` MUST revert
  `MaxExtrasArityExceeded` before any storage read;
- `bump_ttl` happy path on a quiet relation: TTL extension to network max
  on both entries, plus emission of `ttl_bumped { tag, new_ttl_ledger }`;
  and the `RelationUnregistered` error when called on an unknown tag;
- every error path enumerated in §4.12;
- proof-bytes replay under the same `tag` (must revert
  `EpochMismatch` or `InvalidProof`, per §4.8.1);
- proof replay under a different `tag` (must revert `InvalidProof`);
- transcript-discipline regression vectors. For each slot
  $i \in \{0, 1, 2, 3, 4, 5, 6, 7\}$, exactly one regression vector in
  which slots $i$ and $(i + 1) \bmod 8$ are transposed in the absorption
  order, with every other slot unchanged. Eight vectors total: seven
  linear adjacent transpositions named `tx_swap_0_1`, `tx_swap_1_2`,
  `tx_swap_2_3`, `tx_swap_3_4`, `tx_swap_4_5`, `tx_swap_5_6`,
  `tx_swap_6_7`, plus one cyclic wraparound transposition
  `tx_swap_wrap_7_0` that swaps the last absorption slot with the
  first. Each MUST revert `InvalidProof`. The eight adjacent
  transpositions provide one failure mode per slot index and
  unambiguous coverage of every absorption position; comprehensive
  transcript-discipline coverage is the load-bearing defence flagged
  in §5.12 (a 6-PI design would catch only one of these eight
  failures, which is why the SEP prefers PI-vector minimality plus
  exhaustive transcript vectors);
- byte-to-Fr packing regression vectors: provide a `pi_schema_hash` and
  a `tag_fr` pair computed under the canonical 31-byte big-endian
  right-pad rule of §4.2.1, alongside the same pair computed under a
  32-byte-with-modular-reduction packing; the latter MUST produce a
  different digest and a proof bound to it MUST revert `InvalidProof`;
- Poseidon2 sponge regression vectors: at minimum, two cases per
  helper. For $H_{\mathrm{bytes}}$, an empty `msg` (so the absorbed
  vector is $(\texttt{dom},\, 0)$, exactly one absorption round) and
  a 32-byte `msg` (two byte-chunks, four absorbed Fr elements, two
  absorption rounds). For $H_{\mathrm{fr}}$, an empty vector
  ($n = 0$, absorbed vector $(\texttt{dom},\, 0)$) and a vector of
  length three ($n = 3$, absorbed vector
  $(\texttt{dom},\, 3,\, a_0,\, a_1,\, a_2)$, requiring zero-pad of
  the final pair). Vectors MUST include the intermediate state after
  each absorption round so an implementation can localise a mismatch;
- slot-1 vk-digest regression: a proof generated with the canonical
  $H_{\mathrm{bytes}}(\texttt{VK\_DIGEST\_TAG\_FR}, \texttt{vk\_digest})$
  in slot 1 MUST verify; a proof generated with `vk_digest` directly
  reduced mod $p$ into slot 1 (the v0.4.0 bug) MUST NOT verify and
  MUST revert `InvalidProof`;
- witness-replay regression vectors *per registered relation*: for a
  one-shot relation, two `apply` calls carrying the same witness
  opening with distinct otherwise-valid statements must result in the
  second reverting `InvalidProof` (the predicate, not the contract, is
  what causes this revert — the vectors confirm the predicate is wired
  correctly).

## Appendix A. Known-answer values for the `*_TAG_FR` domain constants

> **Normative status of this appendix in v0.4.3.** The five hex
> values in the table below are placeholders. §A.2 makes them
> prerequisite to every other conformance vector in §8;
> consequently, **this SEP is not implementable end-to-end at
> v0.4.3**. The placeholders are pinned in v0.5.0 once a reference
> Poseidon2 implementation publishes the per-round intermediate-state
> tables required by the §A.1 pinning procedure. Implementations
> targeting v0.4.3 may stub the `*_TAG_FR` constants for development
> but MUST NOT ship to mainnet against this version.

The five domain-separation constants of §4.2.1 are derived once via
$H_{\mathrm{bytes}}(\mathbf{0},\, \text{ASCII source string})$.
Independent implementations MUST agree on these specific Fr values
before any other digest in this SEP can be computed consistently. A
packing-rule bug or sponge-mode bug in deriving the constants
themselves would cascade through every subsequent
`pi_schema_hash`, `tag_fr`, `extras_root`, and transcript slot and
would remain invisible until full conformance vectors run; pinning
them here turns that risk into a single known-answer test (KAT) at
the foundation of the spec's hash discipline.

| Constant             | Source string         | Length | Value (Fr, 32-byte big-endian, hex)          |
|----------------------|------------------------|--------|----------------------------------------------|
| `TRANSCRIPT_TAG_FR`  | `"AGMK/v1/transcript"` | 18 B   | *To be pinned — see procedure below*         |
| `TAG_TAG_FR`         | `"AGMK/v1/tag"`        | 11 B   | *To be pinned*                               |
| `EXTRAS_TAG_FR`      | `"AGMK/v1/extras"`     | 14 B   | *To be pinned*                               |
| `SCHEMA_TAG_FR`      | `"AGMK/v1/pi-schema"`  | 17 B   | *To be pinned*                               |
| `VK_DIGEST_TAG_FR`   | `"AGMK/v1/vk-digest"`  | 17 B   | *To be pinned*                               |

The hex values MUST be pinned before this SEP exits Draft status
(targeted for v0.5.0).

### A.1 Pinning procedure

1. Implement the canonical Poseidon2 permutation per §4.2.1
   parameters $(t = 3, \alpha = 5, R_F = 8, R_P = 56)$ over BLS12-381
   $\mathbb{F}_r$, using the round-constants and MDS matrix derived
   per Grassi–Khovratovich–Schofnegger (ePrint 2023/323) for that
   parameter triple. Cross-check the permutation against the official
   Poseidon2 reference test vectors before proceeding.
2. Implement the canonical sponge per §4.2.1: rate $r = 2$,
   capacity $c = 1$, all-zero IV, additive absorption with
   zero-padding of odd-length inputs, single-element squeeze of
   $s_0$.
3. Implement $H_{\mathrm{bytes}}$ per §4.2.1: 31-byte big-endian
   chunks, right-zero-pad the final chunk to 31 bytes, length-prefix
   the absorbed sequence with $\mathrm{len}_{\mathrm{Fr}}(\text{msg})$.
4. For each row of the table above, invoke
   $H_{\mathrm{bytes}}(\mathbf{0},\, \text{ASCII bytes of the source string})$
   and serialise the output Fr element as 32 bytes big-endian per
   CAP-0059. The result populates the table cell.
5. Publish, alongside the pinned hex values:
   - the intermediate sponge state $(s_0, s_1, s_2)$ after each
     absorption round, for each of the five constants — so any
     independent implementer can localise a divergence to the
     packing step, the absorption step, or the permutation step;
   - the byte-level breakdown showing how each source string packs
     into 31-byte chunks (the longest, `AGMK/v1/transcript` at 18
     bytes, fits in one chunk with 13 trailing zero bytes; the
     shortest, `AGMK/v1/tag` at 11 bytes, fits in one chunk with 20
     trailing zero bytes).

### A.2 Conformance against this appendix

Every conformance harness for this SEP MUST validate that its
implementation of $H_{\mathrm{bytes}}$ produces the table's pinned
hex values for the five source strings, **before** running any other
conformance vector from §8. An implementation that disagrees on any
of these five values will disagree on every subsequent digest and
will fail every downstream test for reasons that are easier to
localise here.

## 9. Changelog

- **0.4.4** (2026-05-18): Added a third §1 scope clarification —
  **"When AGMK is the right shape"** — explicitly positioning AGMK
  as complementary to the baked-vk pattern, not a strict
  improvement over it. For governance types whose vk family is
  fixed at deploy time (anarchy, tyranny, oneonone in the current
  `onym-contracts` family), baking the vk into the contract WASM is
  simpler and cheaper than going through `register_relation`. AGMK's
  value is dynamic / extensible / third-party-published relations.
  Closes a misreading risk where reviewers could assume AGMK
  obsoletes the existing fixed-vk contracts.
- **0.4.3** (2026-05-17): Third external-reviewer pass — seven
  targeted fixes. (1) **LCA formula off-by-one in §4.8.2(a)**
  corrected: equality range is now $h_{\mathrm{LCA}} \le \ell \le D - 1$
  (was $h_{\mathrm{LCA}} < \ell \le D - 1$), including the level at
  the LCA itself where both paths share the LCA's sibling. (2) **LCA
  prose rewritten** to identify the cross-related level as
  $h_{\mathrm{LCA}} - 1$ (was incorrectly $h_{\mathrm{LCA}}$), with a
  worked example for $D = 4$, $\mathsf{idx}_a = 5$, $\mathsf{idx}_e = 6$.
  Implementations following v0.4.2 literally were still sound by
  Poseidon2 collision resistance, but the spec text now matches what
  an LCA-precise constraint actually requires. (3) **§4.4 contract
  trait** rewritten to idiomatic Soroban `#[contract] struct` +
  `#[contractimpl] impl` form instead of `#[contract] trait`, which
  does not compile under the SDK. (4) **`InstanceKey::ProtocolVersion`
  removed**; `protocol_version()` now returns the hard-coded constant
  `1`, fixing the fresh-deployment read failure where the storage
  entry was never initialised. (5) **§8 transcript permutation
  vectors** split into seven linear adjacent transpositions plus one
  explicit cyclic wraparound `tx_swap_wrap_7_0`, removing the
  ambiguity in the prior `tx_swap_7_0` naming. (6) **Appendix A**
  prefaced with an explicit non-implementability notice for v0.4.3
  pending v0.5.0's pinned hex values. (7) **`vk_digest_fr` promoted
  to a normative `RelationRecord` field**, computed once at
  `register_relation` time, removing the per-`apply` sponge
  recomputation; added matching view function, event-payload field,
  and conformance vector.
- **0.4.2** (2026-05-17): Four targeted reviewer fixes. (1)
  **§4.8.2(a) two-witness compatibility precision**: replaced the
  informal "where they intersect, they agree" with an explicit LCA
  formulation — $\mathsf{path}_a[\ell] = \mathsf{path}_e[\ell]$ for
  $h_{\mathrm{LCA}} < \ell \le D - 1$, with clarification of which
  levels are independent, which are recomputed siblings, and which
  must be bit-identical. (2) **§8 transcript-permutation vectors**:
  pinned the eight adjacent-transposition vectors
  (`tx_swap_0_1`, …, `tx_swap_7_0`) rather than the prior informal
  "at least one permutation per slot" phrasing. (3)
  **`MAX_EXTRAS_ARITY` justified**: 32 × 32 bytes = 1024 bytes,
  above realistic relation needs (0–4 typical), below the Soroban
  `Vec<BytesN<32>>` deserialisation gas-cost knee. (4) **Added
  Appendix A**: known-answer-value table for the five `*_TAG_FR`
  domain constants with placeholders, pinning procedure, and the
  normative requirement that conformance harnesses validate them
  before any other vector. Actual hex values to be filled in
  v0.5.0 once a reference Poseidon2 implementation is published.
- **0.4.1** (2026-05-17): Second external-reviewer pass — closed two
  remaining inconsistencies. (1) **Pinned the Poseidon2 sponge mode**
  in §4.2.1: rate $r = 2$ / capacity $c = 1$ over the $t = 3$ state,
  all-zero IV, additive absorption with zero-pad of odd-length inputs
  (collision-free under length-prefixing), squeeze of $s_0$.
  Previously the spec deferred to "CAP-0075's canonical sponge
  instantiation", but CAP-0075 exposes only the permutation, leaving
  rate/capacity/IV/absorption/squeeze unspecified. (2) **Fixed §4.7
  slot 1** to use $H_{\mathrm{bytes}}(\texttt{VK\_DIGEST\_TAG\_FR},
  \texttt{record.vk\_digest})$, eliminating the inline 32-byte
  mod-$p$ embedding that §4.2.1 explicitly forbids. Added
  `VK_DIGEST_TAG_FR` to the domain constants table. §8 conformance
  set extended with sponge-mode and slot-1 regression vectors.
- **0.4.0** (2026-05-17): External-reviewer pass. (1) **Fixed slot-0 bug**
  in §4.7 — replaced the broken "18-byte literal in a 16-byte slot" with
  a `TRANSCRIPT_TAG_FR` Fr-element constant derived once via
  $H_{\mathrm{bytes}}$. (2) **Pinned byte-to-Fr packing convention** in
  new §4.2.1: 31-byte big-endian chunks, right-zero-pad final chunk, no
  modular reduction; defined $H_{\mathrm{bytes}}$ and $H_{\mathrm{fr}}$
  helpers used throughout. (3) **Added §4.5.1** stating the minimum
  semantic shape of a registered predicate (sole-authority binding of
  $C_g$, deterministic update function, cross-relation tag binding).
  (4) **Elaborated §4.8.2(a)** to spell out the two-leaf-update
  structure, two-witness compatibility constraint, and `SPENT`-sentinel
  responsibility. (5) **Removed `RootUnchanged` and `EmptyNewRoot`**
  checks from `apply`; both were contract opinions about predicate
  output that violate the neutrality principle. Rationale in new §5.11.
  (6) **Added `MAX_EXTRAS_ARITY = 32`** trait-level constant and
  `MaxExtrasArityExceeded` error. (7) **Added `registrant: Address`**
  to `register_relation` with `require_auth(registrant)`; published in
  `RelationRecord`, `relation_registered` event, and new
  `registrant(tag)` view. Rationale in new §5.13. (8) **Added
  `ttl_bumped` event** on `bump_ttl` success and **pinned the TTL bump
  policy** to unconditional `extend_ttl(max - 1, max)` (no thresholding
  ambiguity). (9) **Pushback documented in §5.12**: kept PI vector at
  five elements and rejected the `pi_schema_hash`-as-6th-PI proposal;
  the correct defence is comprehensive transcript-discipline conformance
  vectors, which §8 now strengthens. (10) **§8 conformance set
  expanded**: cross-caller squat test, byte-packing regression vectors,
  TTL-exactly-max verification, `MaxExtrasArityExceeded` paths.
- **0.3.1** (2026-05-17): Front-loaded two scope clarifications in §1
  to preempt reviewer confusion: (a) whitepaper Theorem 1 covers only
  the admission predicate — non-admission relations require their own
  soundness arguments; (b) permissionless registration means tag
  presence on chain is not a trust attestation, and users must verify
  `(vk_digest, pi_schema_hash, bootstrap_root)` out of band. §5.6
  hardened with an explicit "Soundness coverage" paragraph repeating
  the same point at the point of relevance. §3 Abstract now opens with
  an "interface, not a canonical registry" disclaimer so the point is
  unmissable for skim readers.
- **0.3.0** (2026-05-17): Added §4.8 (replay protection — proof-bytes
  enforced by the contract, witness-level by the predicate, with two
  recommended patterns) and §4.9 (storage TTL strategy: network-max
  bump on every apply, permissionless `bump_ttl(tag)` for quiet
  relations, archival is a chain-level concern). Added `bump_ttl` to
  the contract trait. Rationales §5.10 and §5.11 added. §6 expanded
  with witness-level replay and state-archival risks.
- **0.2.0** (2026-05-17): Removed admin / `init` / `revoke_admin` /
  `set_paused`. `register_relation` is now permissionless. Renamed the
  state-advancement entry point from `admit` to `apply` and the
  corresponding event from `admitted` to `applied`, to reflect that the
  contract is neutral about whether a registered relation expresses
  admission, removal, key rotation, or any other
  $\mathcal{R}_{\text{Upd}}$-shaped transition. Errors renumbered.
- **0.1.0** (2026-05-17): Initial draft. Generic relation interface; no
  governance types normative. Single contract; relation registry indexed
  by `Symbol`; fixed five-element PI vector; immutable `(tag, vk)`
  registrations.

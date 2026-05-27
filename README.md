# turbo prune resolves a hoisted workspace's transitive dependency out of its semver range

`turbo prune --docker` emits a pruned Bun lockfile in which a **hoisted** workspace
dependency is linked to a transitive dependency **outside its declared semver range**,
having dropped the correct version. A subsequent `bun install` on the pruned lockfile
then installs that out-of-range version. Under bun (the runtime these apps use) this can
break at import time.

Verified on the turbo **`canary`** dist-tag (pinned in `package.json` / `bun.lock` —
currently **`turbo@2.9.16-canary.2`**) with **bun 1.3.14**.

## The dependency shape

`bs58` is published in three majors, each requiring a different major of `base-x`:

| package | requires |
| ------- | -------- |
| `bs58@5.0.0` | `base-x@^4` |
| `bs58@6.0.0` | `base-x@^5` |

`base-x@5` changed its CommonJS export to a non-callable object, so `bs58@5` (which does
`module.exports = require('base-x')(ALPHABET)`) throws `TypeError: basex is not a function`
if it is ever linked against `base-x@5`.

This monorepo has:

- workspace **root** → `bs58@5.0.0` (so `bs58@5` is the hoisted/top-level version)
- `apps/app` (the prune target) → `bs58@6.0.0` + `@repro/lib`
- `packages/lib` → `bs58@5.0.0`

In a normal install bun scopes this correctly: top-level `bs58@5` → `base-x@4.0.1`, and
`apps/app`'s `bs58@6` → `base-x@5.0.1`.

> Note: the root `bs58@5` dependency is just a deterministic way to make `bs58@5` the
> hoisted version in this tiny repo. In a large real monorepo this happens naturally when
> many packages share the older major. This is exactly how we hit it: a workspace that
> imports `bs58@5` started crashing in its Docker image after `turbo prune` + `bun install`.

## Reproduce

```sh
docker build --no-cache -t turbo-prune-repro .
```

The build fails at the final step.

## Expected

The pruned lockfile keeps `base-x@4` for the hoisted `bs58@5`, so `bs58@5` is linked to
`base-x@4.0.1` and `import bs58 from 'bs58'` works.

## Actual

The pruned `out/json/bun.lock` drops `base-x@4` entirely; the only `base-x` left for the
top-level `bs58@5` (which requires `base-x@^4`) is `base-x@5.0.1`. After `bun install`:

```
node_modules/.bun/bs58@5.0.0/node_modules/base-x -> ../../base-x@5.0.1/node_modules/base-x
```

`bs58@5` is linked to `base-x@5.0.1` (out of its `^4` range), and importing it under bun
throws:

```
TypeError: basex is not a function.
  at .../bs58@5.0.0/node_modules/bs58/index.js:4:18
```

The root `bun.lock` is correct; only the pruned lockfile is wrong.

## Related

Likely the same area as the (closed) Bun-lockfile prune issues
[#12653](https://github.com/vercel/turborepo/issues/12653) and
[#12744](https://github.com/vercel/turborepo/issues/12744), but a different symptom: those
produced a lockfile `bun install --frozen-lockfile` rejected; here the pruned lockfile is
accepted but resolves a dependency outside its semver range.

## Environment

- turbo: `canary` (`2.9.16-canary.2`)
- bun: `1.3.14`
- package manager: bun workspaces

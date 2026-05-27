# Reproduction: `turbo prune` emits a pruned Bun lockfile that resolves a hoisted
# workspace's transitive dependency to a version OUTSIDE its declared semver range,
# dropping the correct version. Verified on the turbo `canary` dist-tag (pinned in
# package.json / bun.lock — currently turbo@2.9.16-canary.2).
#
#   docker build --no-cache -t turbo-prune-repro .
FROM oven/bun:1.3.14
WORKDIR /repro
COPY . .

# Install (pins the canary turbo from bun.lock), then prune with that exact turbo binary.
RUN bun install
# Prune the app workspace (+ its workspace dep `lib`). The pruned tree legitimately
# contains bs58@5 (hoisted, requires base-x@^4) and bs58@6 (requires base-x@^5).
RUN ./node_modules/.bin/turbo prune @repro/app @repro/lib --docker

WORKDIR /repro/out/json
RUN bun install

# bs58@5 requires base-x@^4, but the pruned lockfile dropped base-x@4 and links it to
# base-x@5.0.1 (out of range). base-x@5's CommonJS export is a non-callable object, so
# importing bs58 throws under bun (the runtime these apps use) -> this step fails.
RUN echo "=== bs58@5 (requires base-x@^4) is linked to: ===" \
 && readlink node_modules/.bun/bs58@5.0.0/node_modules/base-x \
 && echo "=== base-x versions present: ===" \
 && ls -d node_modules/.bun/base-x@* \
 && echo "=== import bs58 under bun (the production runtime) ===" \
 && printf "%s\n" "import bs58 from 'bs58';" "console.log('bs58.encode ->', bs58.encode(Buffer.from([1, 2, 3])));" > check.mjs \
 && bun check.mjs

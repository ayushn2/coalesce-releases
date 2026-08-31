# Coalesce Releases

Prebuilt binaries for the Coalesce node. Source code is not published here.

Coalesce is a **multi-party payment channel**: a group shares one on-chain Bitcoin
UTXO (a "hyperedge") and pays each other off-chain, settling to the blockchain only
on open/close. There is no server and no coordinator — every node holds only its own
key share and wallet.

## Install

```bash
curl -sSL https://raw.githubusercontent.com/ayushn2/coalesce-releases/main/install.sh | bash
```

Detects your OS/arch and installs `coalesce-node` — **never with sudo**. It
picks a directory that is already on your PATH and writable by your user
(e.g. Homebrew's bin dir), so on most machines there's nothing else to do;
only if no such directory exists does it fall back to `~/.local/bin` and
print the one-line PATH addition. Pick the location yourself with
`COALESCE_INSTALL_DIR=<dir>`.

Windows users: download the `.exe` asset directly from the [Releases](https://github.com/ayushn2/coalesce-releases/releases) page.

macOS/Linux users can instead install via Homebrew:

```bash
brew install ayushn2/tap/coalesce
```

## Prerequisite: you need a live signet Bitcoin node

Coalesce runs on Bitcoin **signet** (free test coins, not mainnet). For any real
use — funding, sending, closing a channel — your machine needs its own **running**
`bitcoind -signet` instance; Coalesce does not include or manage this for you.

```bash
# Install Bitcoin Core from https://bitcoincore.org/en/download, then:
bitcoind -signet -daemon

bitcoin-cli -signet createwallet mywallet
bitcoin-cli -signet -rpcwallet=mywallet getnewaddress
# Fund the address from a signet faucet (search "bitcoin signet faucet")
```

Coalesce authenticates to your node automatically via its cookie file — no RPC
username/password needed for a default `bitcoind -signet` setup.

> You can try Coalesce **without** any Bitcoin node using the local demo below —
> it uses simulated balances. A live signet node is only required once you want to
> move real signet BTC.

## Quick local demo (no Bitcoin needed)

Runs a 3-member hyperedge on one machine with pretend balances:

```bash
coalesce-node init -dir ./demo -nodes 3 -base-port 9000 -balance 100000000

# in 3 separate terminals:
coalesce-node run -config ./demo/node0.json
coalesce-node run -config ./demo/node1.json
coalesce-node run -config ./demo/node2.json
```

At any node's prompt: `bal`, `send node1 5000`, `propose`, `bal`, `quit`.

## Networking

NAT traversal is automatic — no flags, no relay/STUN server to run. If a
direct connection to a peer isn't reachable, your node falls back to
hole-punching or relaying through a peer you're already connected to on
its own. For best connectivity, forward your advertised `-addr host:port`
for **both TCP and UDP**. To pin the relay listener to a fixed port
instead of a random one, set `COALESCE_RELAY_PORT` (see environment
variables below).

## Real use on signet

```text
   form cluster   →   group key   →   put money in   →   transact   →   take money out
   (bootstrap)        (keygen)        (dfund)            (send)         (coopclose)
```

1. **Get a signet node + funded wallet** — see prerequisite above.
2. **Form the cluster with `bootstrap`.** Everyone runs one command with the
   SAME `-peers` list; it exchanges public identity bundles over authenticated
   connections (no private key ever crosses the wire, no manual file copying)
   and continues straight into running your node — no separate `run` step:

   ```bash
   export COALESCE_BTC_NET=signet
   export COALESCE_BTC_HOST=localhost:38332

   coalesce-node bootstrap -dir ./me -addr 1.2.3.4:9000 \
     -peers "1.2.3.4:9000,5.6.7.8:9001,9.10.11.12:9002" \
     -wallet mywallet -enforce
   ```

   `-enforce` (self-protection, recommended) is safe to pass now — it
   activates automatically once the cluster is funded. Forgot `-wallet`? Type
   `attach-wallet <name>` at the prompt later — no restart needed.
3. **Generate the group key** — once everyone is running, any member types
   `keygen`. Dealerless: no machine ever holds the full key. Each node
   restarts itself automatically to load its share.
4. **Fund the channel** — every member independently types `dfund <sats>` with
   whatever amount THEY want to commit (any value up to their wallet balance).
   Your payout destination defaults to this same wallet; override with
   `dfund <sats> [fee] <address>`. Once every member has run `dfund`, each
   node restarts automatically into the funded channel.
5. **Transact** — `bal`, `send <peer> <sats>`. Checkpoints finalize
   automatically (`propose` forces one early).
6. **Take money out** — any member types `coopclose`. Everyone co-signs one
   closing transaction; the full settlement prints before broadcasting, and
   your node reports your final payout once it confirms. The cluster is then
   permanently closed — `bal` shows the final on-chain payouts, further
   sends/closes are refused, and this survives restarts.

### Other ways to form a cluster

| Method | When | Trade-off |
|---|---|---|
| `bootstrap -discover -want <n> [-room <name>]` | You don't know the other members — find strangers via public Nostr relays | Proves key ownership via signed challenge-response, not real-world identity |
| `identity` + `assemble` | You want to inspect every bundle yourself, or you're air-gapped | Manual file passing; same no-shared-private-keys property |
| `init -distributed -hosts ...` | One trusted operator sets up everyone (demos) | That machine transiently holds every member's identity key |

These produce config files only — start your node afterward with
`coalesce-node run -config nodeI.json -wallet mywallet -enforce`. See
`coalesce-node <cmd> -h` for flags.

### What to expect at the prompt

The prompt narrates everything in plain wording ("cluster", not protocol
jargon), so these are the only behaviors worth knowing in advance:

- **Ceremonies tolerate stragglers.** `keygen` and `dfund` re-announce for a
  while, so a briefly-disconnected peer catches up — don't retype commands.
  If `keygen` makes no progress for a couple of minutes, Ctrl-C every node
  and retry.
- **`dfund` may put one prep transaction on-chain first** (to make a coin of
  your exact amount), bidding your node's live fee estimate; it warns every
  10 minutes if confirmation is slow.
- **Nothing runs on placeholder numbers.** Before funding completes,
  `send`/`propose`/`coopclose` refuse; over-balance sends are refused with
  exact figures; payments show as "unconfirmed (pending checkpoint)" until a
  checkpoint locks them in; a proposer can never confirm anything by itself.
- **Startup always re-checks whether the cluster is still open on-chain** —
  even if you were offline when it closed. If it finds a recognized
  cooperative close, it reports the final settled payouts itself and `bal`
  shows those. If it finds a spend it can't recognize, it prints a WARNING
  and refuses `send`/`propose`/`coopclose` until that's resolved, rather
  than risk acting on stale balances.

## Command reference

**CLI subcommands** (`coalesce-node <cmd> -h` for flags):

| Command | What it does |
|---|---|
| `bootstrap` | Set up a cluster over the network and continue straight into running it — no manual file passing, no separate `run` step. `-dir <dir>`; `-addr <host:port>`; `-peers <addr0,addr1,...>` (known members) or `-discover -want <n> [-room <name>]` (find strangers via public Nostr relays); `-quorum <N>`; `-balance <sats>`; `-wallet`/`-enforce`/`-verbose`/`-auto-root-depth`/`-auto-root-fallback` (same as `run`, carried straight through). Every connection is authenticated with a pubkey-pinned challenge-response. Recommended for real, multi-operator setups. |
| `identity` | Generate your own identity key locally. `-dir <dir>`; `-addr <host:port>` (your advertised address). Manual alternative to `bootstrap` — pairs with `assemble`. |
| `assemble` | Assemble a cluster from public identity bundles produced by `identity`. `-dir <dir>`; `-bundles <b0.json,b1.json,...>`; `-quorum <N>` (default: supermajority); `-balance <sats>`. No private key material is ever read or written. |
| `init` | Generate cluster configs in one step. `-distributed` = shareless; `-hosts`; `-nodes`, `-base-port`, `-balance`. Quicker than `bootstrap`/`identity`+`assemble`, but the operator running it transiently holds every participant's identity private key. |
| `run` | Run a node. `-config <file>` (required); `-wallet <name>` (enables funding); `-enforce` (self-protection); `-auto-root-depth <N>` (override the automatic-checkpoint threshold; 0 disables it); `-auto-root-fallback <dur>` (override the fallback-proposer timing); `-verbose` (print internal protocol diagnostics). |
| `fund` / `close` | Coordinator-run funding/closing — one machine holds all wallets, for demos/testing only. Prefer `dfund`/`coopclose` for real use. |

**Prompt commands** inside `run`:

| Command | What it does |
|---|---|
| `keygen` | Generate the group key distributed-ly (shareless clusters). Auto-restarts the node when done. |
| `attach-wallet <name>` | Wire up a bitcoind wallet for `dfund`, live, if the node wasn't started with `-wallet`. No restart needed. |
| `dfund <amountSat> [fee] [address]` | Commit YOUR OWN contribution (any amount, in sat) from your own wallet; optionally choose your close payout destination. Auto-restarts once your deposit confirms. |
| `send <peer> <sats>` | Pay another member. Over-balance sends are refused upfront with exact committed/pending/available figures. |
| `propose` | Finalize a checkpoint (locks in payments) — usually automatic, see above |
| `bal` | Show balances. On a closed cluster, shows the final payouts paid by the close transaction instead. |
| `coopclose [fee]` | Cooperatively close — pays each member out to their chosen settlement address, printing the full settlement before broadcasting. Refuses on an already-closed cluster. |
| `cond <connector> <destHE> <receiver> <sats> <timeout>` | Multi-hop payment across hyperedges |
| `watch <heID> <txid> <vout>` | Watch a funding output on-chain |
| `quit` | Shut down (Ctrl-C also works) |

**Environment variables:**

| Variable | Meaning |
|---|---|
| `COALESCE_BTC_NET` | `signet` (or `regtest`) |
| `COALESCE_BTC_HOST` | your bitcoind RPC host, e.g. `localhost:38332` |
| `COALESCE_BTC_COOKIE` | override the cookie path (default: the standard signet cookie) |
| `COALESCE_BTC_USER` / `COALESCE_BTC_PASS` | RPC user/pass (only if you don't use cookie auth) |
| `COALESCE_RELAY_PORT` | Pin the relay listener to a fixed port instead of a random one |

## Safety notes

- **Signet only, experimental.** Free test coins. Do not use mainnet BTC.
- Funds are safe as long as **more than two-thirds** of members are honest (standard
  threshold assumption). A single honest node can always recover its own money.
- Run with `-enforce` for real use so your node defends itself automatically.
- Keep your `nodeX.key` file private — it is your identity in the group.
- `bootstrap -discover` proves you're connecting to whoever holds a given
  keypair (via a signed challenge-response), not that they're a specific
  real-world person — the inherent limit of meeting any stranger over a
  network, not a lesser guarantee unique to this feature. `bootstrap`'s
  discovery publishes small signed ads to public Nostr relays; nothing
  sensitive is in them (address, pubkey, cluster size), but they are public.
- This distribution is binary-only: since the source isn't published yet, you are
  trusting that this binary matches its claimed behavior. Source will be made public
  in the future.
- **Migration note (v0.1.6+):** `dfund` now records a settlement destination for
  each member. A hyperedge funded with an older version has no destination on file,
  and `coopclose` will refuse to run rather than guess — you'll need to add a
  `settlement_pkscript` (hex-encoded scriptPubKey) to each peer entry in every
  member's config file before closing such a cluster.

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

Detects your OS/arch and installs `coalesce-node` to `/usr/local/bin`.

Windows users: download the `.exe` asset directly from the [Releases](https://github.com/ayushn2/coalesce-releases/releases) page.

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

## Real use on signet

```
   set up keys   →   put money in   →   transact   →   take money out
   (keygen/init)     (fund/dfund)       (run)          (close/coopclose)
```

1. **Get a signet node + funded wallet** — see prerequisite above.
2. **Create the cluster.** A few ways to do this, from most to least automatic:
   - **Recommended: `bootstrap`.** Every member agrees out-of-band on everyone's
     address, then everyone runs one command with the SAME list:
     ```bash
     coalesce-node bootstrap -dir ./me -addr 1.2.3.4:9000 \
       -peers "1.2.3.4:9000,5.6.7.8:9001,9.10.11.12:9002"
     ```
     One member is deterministically elected coordinator (every node computes
     the same answer independently — no voting). Everyone else sends the
     coordinator their public identity bundle over the network; the
     coordinator assembles the cluster and sends each member's config back
     over the same connection — no manual file copying at all. Every
     connection proves, via a signed challenge-response, that whoever's on the
     other end really holds the private key for the address they claim.
   - **Don't personally know the other members? Add `-discover`.** Finds
     strangers via public Nostr relays instead of a pre-agreed address list —
     the same way a brand-new Lightning node can open a channel with someone
     it found on the public network:
     ```bash
     coalesce-node bootstrap -dir ./me -addr 1.2.3.4:9000 -discover -want 3 -room "some-memorable-name"
     ```
     Only a shared "room" name needs agreeing on (post it anywhere — a forum,
     a chat), not addresses or keys. Leave `-room` unset to join one shared
     public pool. This proves you're really talking to whoever holds a given
     key — it does not vet that they're a specific real-world person you
     know, since there isn't one to check against for a true stranger; that's
     the same trust level a first-time Lightning peer has.
   - **Manual alternative: `identity` + `assemble`.** Same security property
     (no machine ever holds another member's private key), but you exchange
     the public bundle files yourself instead of over the network — useful if
     you want to eyeball what you're assembling, or you're air-gapped:
     ```bash
     # each member, on their own machine:
     coalesce-node identity -dir ./me -addr 1.2.3.4:9000   # your own public IP:port
     # → writes ./me/self.key (PRIVATE, keep it) and ./me/self.pub.json (send this)
     ```
     Once everyone has shared their `self.pub.json`, any one member assembles
     the cluster from those public bundles:
     ```bash
     coalesce-node assemble -dir ./cluster \
       -bundles alice.pub.json,bob.pub.json,carol.pub.json
     ```
     This produces `node0.json`, `node1.json`, `node2.json` — none contain any
     private key material, so they're safe to send back to each participant.
     Each participant places their own `nodeI.json` next to the `self.key` they
     generated above.
   - **Quickest alternative:** one member creates the cluster for everyone,
     listing every participant's real address:
     ```bash
     coalesce-node init -dir ./cluster -nodes 3 -distributed \
       -hosts "1.2.3.4,5.6.7.8,9.10.11.12"
     ```
     This produces per-member bundles (`nodeI.json` + `nodeI.key`) — send each
     participant only their own bundle. Simpler, but that member's machine
     transiently holds everyone's identity private key before sending it out.
3. **Each participant starts their own node**, pointed at their own signet node:
   ```bash
   export COALESCE_BTC_NET=signet
   export COALESCE_BTC_HOST=localhost:38332
   coalesce-node run -config nodeI.json -wallet mywallet -enforce
   ```
   `-enforce` turns on self-protection — recommended for real use.
4. **Once everyone is running**, any member types `keygen` to generate the group
   key via a dealerless, distributed protocol — no machine ever holds the full key.
   Each node automatically restarts itself afterward to load its new share. Every
   member keeps re-announcing the start of this ceremony for a couple of minutes,
   so a peer that missed the very first trigger (still connecting, a brief network
   hiccup) still gets a chance to join. If keygen still seems stuck with no
   progress after a couple of minutes, it's safest to Ctrl-C every node and retry
   from scratch — the key-generation round itself doesn't yet retry a dropped
   message on its own once underway.
5. **Fund the channel** — every member independently types `dfund <sats>` at their
   own prompt with **whatever amount they want to commit** (e.g. `dfund 40000`,
   `dfund 2300000` — any value up to their wallet's spendable balance, not just
   one contribution amount decided by a single member). If your wallet doesn't
   already hold a coin of exactly that size, your node automatically prepares one
   on-chain first, then waits for it to confirm before proceeding — you'll see this
   happen in your node's output. `dfund` also records where **your** eventual
   payout should go: by default a fresh address in this same wallet, or pass one
   explicitly — `dfund <sats> [fee] <address>` — to send it somewhere else. This is
   completely separate from your node's protocol identity key; that key is never
   used as a Bitcoin destination. Once every member has run `dfund`, each node
   automatically restarts to open the funded channel. Each member keeps
   re-announcing its own deposit/signature every few seconds until the whole
   ceremony completes, so a peer that missed one broadcast (still connecting,
   a brief network hiccup) catches up automatically — you don't need to retype
   `dfund` if another member is slow to respond.
6. **Transact** at the prompt: `bal`, `send <peer> <sats>`. Before the channel is
   actually funded on-chain, `send`/`cond`/`propose`/`coopclose` refuse to run (and
   `bal` shows a clear notice) rather than silently operating on placeholder
   numbers — wait for `dfund` to fully complete first. Trying to send more than
   you actually have committed also fails with a clear message instead of silently
   doing nothing. Every payment prints a plain confirmation to every member —
   "Sent"/"Received"/"Observed" — marked **unconfirmed (pending checkpoint)** until
   a `propose` locks it in. You don't usually need to run `propose` yourself: a node
   automatically proposes one once enough unconfirmed payments build up (tune with
   `-auto-root-depth`), and it still works as a manual command any time you don't
   want to wait. Every member also sees that it independently checked the proposed
   confirmation against its own records before co-signing — a proposer can never
   confirm anything by itself.
7. **Exit / take money out** — any member types `coopclose`; everyone co-signs one
   closing transaction paying each member out to the settlement address they chose
   during `dfund`. The full settlement (who gets what, and the fee) prints before
   broadcasting, and each member's node then waits for the closing transaction to
   actually confirm on-chain before reporting its own final payout and that the
   cluster is closed — not just that it broadcast. `send`/`cond`/`propose` refuse
   to run once any member has requested a close, since anything sent after that
   point would never be reflected in the (already-signed) closing transaction.
   All of this uses plain, non-technical wording at the prompt — you won't see
   protocol jargon like "hyperedge" in normal use, only "cluster."

## Command reference

**CLI subcommands** (`coalesce-node <cmd> -h` for flags):

| Command | What it does |
|---|---|
| `bootstrap` | Bootstrap a cluster over the network — no manual file passing at all. `-dir <dir>`; `-addr <host:port>`; `-peers <addr0,addr1,...>` (known members) or `-discover -want <n> [-room <name>]` (find strangers via public Nostr relays); `-quorum <N>`; `-balance <sats>`. Every connection is authenticated with a pubkey-pinned challenge-response. Recommended for real, multi-operator setups. |
| `identity` | Generate your own identity key locally. `-dir <dir>`; `-addr <host:port>` (your advertised address). Manual alternative to `bootstrap` — pairs with `assemble`. |
| `assemble` | Assemble a cluster from public identity bundles produced by `identity`. `-dir <dir>`; `-bundles <b0.json,b1.json,...>`; `-quorum <N>` (default: supermajority); `-balance <sats>`. No private key material is ever read or written. |
| `init` | Generate cluster configs in one step. `-distributed` = shareless; `-hosts`; `-nodes`, `-base-port`, `-balance`. Quicker than `bootstrap`/`identity`+`assemble`, but the operator running it transiently holds every participant's identity private key. |
| `run` | Run a node. `-config <file>` (required); `-wallet <name>` (enables funding); `-enforce` (self-protection); `-auto-root-depth <N>` (override the automatic-checkpoint threshold; 0 disables it); `-auto-root-fallback <dur>` (override the fallback-proposer timing); `-verbose` (print internal protocol diagnostics). |
| `fund` / `close` | Coordinator-run funding/closing — one machine holds all wallets, for demos/testing only. Prefer `dfund`/`coopclose` for real use. |

**Prompt commands** inside `run`:

| Command | What it does |
|---|---|
| `keygen` | Generate the group key distributed-ly (shareless clusters) |
| `dfund <amountSat> [fee] [address]` | Commit YOUR OWN contribution (any amount, in sat) from your own wallet; optionally choose your close payout destination |
| `send <peer> <sats>` | Pay another member |
| `propose` | Finalize a checkpoint (locks in payments) — usually automatic, see above |
| `bal` | Show balances |
| `coopclose [fee]` | Cooperatively close — pays each member out to their chosen settlement address, printing the full settlement before broadcasting |
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

## Safety notes

- **Signet only, experimental.** Free test coins. Do not use mainnet BTC.
- Funds are safe as long as **more than two-thirds** of members are honest (standard
  threshold assumption). A single honest node can always recover its own money.
- Run with `-enforce` for real use so your node defends itself automatically.
- Keep your `nodeX.key` file private — it is your identity in the group.
- `bootstrap -discover` proves you're connecting to whoever holds a given
  keypair (via a signed challenge-response), not that they're a specific
  real-world person — the same trust level as a first-time Lightning peer,
  not a lesser guarantee unique to this feature. `bootstrap`'s discovery
  publishes small signed ads to public Nostr relays; nothing sensitive is in
  them (address, pubkey, cluster size), but they are public.
- This distribution is binary-only: since the source isn't published yet, you are
  trusting that this binary matches its claimed behavior. Source will be made public
  in the future.
- **Migration note (v0.1.6+):** `dfund` now records a settlement destination for
  each member. A hyperedge funded with an older version has no destination on file,
  and `coopclose` will refuse to run rather than guess — you'll need to add a
  `settlement_pkscript` (hex-encoded scriptPubKey) to each peer entry in every
  member's config file before closing such a cluster.

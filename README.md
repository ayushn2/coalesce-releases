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

At any node's prompt: `bal`, `send node1 5000`, `root`, `bal`, `quit`.

## Real use on signet

```
   set up keys   →   put money in   →   transact   →   take money out
   (keygen/init)     (fund/dfund)       (run)          (close/coopclose)
```

1. **Get a signet node + funded wallet** — see prerequisite above.
2. **One member creates the shareless cluster**, listing every participant's real
   address:
   ```bash
   coalesce-node init -dir ./cluster -nodes 3 -distributed \
     -hosts "1.2.3.4,5.6.7.8,9.10.11.12"
   ```
   This produces per-member bundles (`nodeI.json` + `nodeI.key`) — send each
   participant only their own bundle.
3. **Each participant starts their own node**, pointed at their own signet node:
   ```bash
   export COALESCE_BTC_NET=signet
   export COALESCE_BTC_HOST=localhost:38332
   coalesce-node run -config nodeI.json -wallet mywallet -enforce
   ```
   `-enforce` turns on self-protection — recommended for real use.
4. **Once everyone is running**, any member types `keygen` to generate the group
   key via a dealerless, distributed protocol — no machine ever holds the full key.
   Each node automatically restarts itself afterward to load its new share.
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
   actually funded on-chain, `send`/`cond`/`root`/`coopclose` refuse to run (and
   `bal` shows a clear notice) rather than silently operating on placeholder
   numbers — wait for `dfund` to fully complete first. Every payment prints a
   plain confirmation to every member — "Sent"/"Received"/"Observed" — marked
   **unconfirmed (pending checkpoint)** until a `root` locks it in. You don't
   usually need to run `root` yourself: a node automatically proposes one once
   enough unconfirmed payments build up (tune with `-auto-root-depth`), and it
   still works as a manual command any time you don't want to wait.
7. **Exit / take money out** — any member types `coopclose`; everyone co-signs one
   closing transaction paying each member out to the settlement address they chose
   during `dfund`. The full settlement (who gets what, and the fee) prints before
   broadcasting, so you can verify it matches what you expect.

## Command reference

**CLI subcommands** (`coalesce-node <cmd> -h` for flags):

| Command | What it does |
|---|---|
| `init` | Generate cluster configs. `-distributed` = shareless (recommended); `-hosts`; `-nodes`, `-base-port`, `-balance`. |
| `run` | Run a node. `-config <file>` (required); `-wallet <name>` (enables funding); `-enforce` (self-protection); `-auto-root-depth <N>` (override the automatic-checkpoint threshold; 0 disables it); `-auto-root-fallback <dur>` (override the fallback-proposer timing); `-verbose` (print internal protocol diagnostics). |
| `fund` / `close` | Coordinator-run funding/closing — one machine holds all wallets, for demos/testing only. Prefer `dfund`/`coopclose` for real use. |

**Prompt commands** inside `run`:

| Command | What it does |
|---|---|
| `keygen` | Generate the group key distributed-ly (shareless clusters) |
| `dfund <amountSat> [fee] [address]` | Commit YOUR OWN contribution (any amount, in sat) from your own wallet; optionally choose your close payout destination |
| `send <peer> <sats>` | Pay another member |
| `root` | Finalize a checkpoint (locks in payments) — usually automatic, see above |
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
- This distribution is binary-only: since the source isn't published yet, you are
  trusting that this binary matches its claimed behavior. Source will be made public
  in the future.
- **Migration note (v0.1.6+):** `dfund` now records a settlement destination for
  each member. A hyperedge funded with an older version has no destination on file,
  and `coopclose` will refuse to run rather than guess — you'll need to add a
  `settlement_pkscript` (hex-encoded scriptPubKey) to each peer entry in every
  member's config file before closing such a cluster.

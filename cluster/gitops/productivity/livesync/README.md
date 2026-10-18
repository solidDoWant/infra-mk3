# Obsidian LiveSync

[Self-hosted LiveSync](https://github.com/vrtmrz/obsidian-livesync) against
[couchgres](https://github.com/couchgres/couchgres) (CouchDB API on Postgres), at
`https://livesync.<domain>` on both gateways. All credentials are in the `livesync` Secret
(`app/livesync.sops.yaml`).

- `app/hr.yaml`: couchgres + Envoy sidecar (CORS, Postgres mTLS) and the config Job.
- `bridge/`: [livesync-bridge](https://github.com/vrtmrz/livesync-bridge),
  mirroring every `vault-*` database to markdown on the `livesync-bridge` PVC (one-way).
- `backup/`: nightly dr-job of the database and the markdown PVC.

Images are built from `container images/couchgres` and `container images/livesync-bridge`.

## Adding a vault

The bridge can only decrypt vaults that use the shared passphrase and ID key, and only
mirrors databases named `vault-<name>`.

1. In the LiveSync setup wizard, choose CouchDB with URI `https://livesync.<domain>`,
   database `vault-<name>`, and the **admin** credentials (only admins can create
   databases).
2. Enable end-to-end encryption with `VAULT_PASSPHRASE`, and path obfuscation.
3. For the ID key, choose **Set an ID key** → **Import an ID recovery code** and paste
   `VAULT_ID_RECOVERY_CODE`.
4. After the first sync, switch the credentials to `SYNC_USERNAME` / `SYNC_PASSWORD`. Use
   those on every other device.

The bridge notices the new database within a minute and restarts to pick it up.

## Limits

- From the internet, only `/_session`, `/_up`, and database paths are reachable (Coraza
  rule 1005). Fauxton (`/_utils`) and server config work on the LAN only, with the admin
  account.
- couchgres caps request bodies at 256MiB and documents at 64MiB.

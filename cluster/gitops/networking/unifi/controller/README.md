# UniFi controller

Single-instance (non-HA) UniFi Network controller. Config is clickops/UI-only —
see the TODO in [`hr.yaml`](./hr.yaml).

- LoadBalancer IP: `10.34.0.4` (Cilium LB-IPAM)
- Inform URL for APs: `http://10.34.0.4/inform` (svc port 80 → container 8080)
- Mongo: bundled MongoDB 3.6, listens only on `127.0.0.1:27117` inside the pod

## Recovering a factory-reset access point

If an AP gets factory-reset (or otherwise drops out and won't re-adopt), the
controller still holds its provisioning state. You can re-adopt it manually by
pushing the controller's stored adoption key onto the AP over SSH, instead of
forgetting/re-adopting it from scratch.

1. **Get the AP's stored adoption key from the controller.** Run the helper
   script with the AP's MAC address:

   ```sh
   ./get-device-authkey.sh aa:bb:cc:dd:ee:ff
   ```

   It prints the device record, including `x_authkey`:

   ```json
   {
     "cfgversion": "0123456789abcdef",
     "mac": "aa:bb:cc:dd:ee:ff",
     "x_authkey": "abcdef0123456789abcdef0123456789"
   }
   ```

   The `x_authkey` value is the adoption key.

2. **SSH into the AP** using the default credentials (`ubnt` / `ubnt` after a
   factory reset; otherwise whatever device SSH credentials were configured):

   ```sh
   ssh ubnt@<ap-ip>
   ```

3. **Set the AP's static IP** (needed so the controller/AP traffic matches the
   network policies). Look up the AP's assigned address in
   [`docs/network.yaml`](../../../../../docs/network.yaml) — e.g. `ap-01` is
   `10.1.0.160`. The management network is `10.1.0.0/16`, so the netmask is
   `255.255.0.0` (**not** `/24`), and the gateway is `10.1.0.254`:

   ```sh
   ifconfig br0 10.1.0.160 netmask 255.255.0.0
   route del default 2>/dev/null; route add -net default gw 10.1.0.254
   ```

   > **Heads up:** the moment `br0` changes IP, your SSH session (still bound to
   > the old IP) drops. Either run the IP change detached so it outlives the
   > disconnect and then reconnect on the new IP:
   >
   > ```sh
   > ssh ubnt@<old-ip> 'nohup sh -c "sleep 2; ifconfig br0 10.1.0.160 netmask 255.255.0.0; route del default 2>/dev/null; route add -net default gw 10.1.0.254" >/tmp/setip.log 2>&1 &'
   > ```
   >
   > …or just SSH back in on the new static IP before doing step 4.

4. **Point the AP at the controller and adopt it**, passing the `x_authkey` from
   step 1 (run this over a *fresh* SSH session to the new static IP):

   ```sh
   syswrapper.sh set-adopt http://10.34.0.4/inform abcdef0123456789abcdef0123456789
   ```

   The AP should re-appear in the controller as adopted (rather than pending),
   keeping its previous identity/config.

   **Verify from the controller, not the AP.** The AP's own status
   (`mca-cli-op info`) stays stale/default for a while after `set-adopt`, so
   don't trust it. Instead confirm the controller's device record flipped —
   query Mongo the same way `get-device-authkey.sh` does and check for
   `adopted: true` / `adoption_completed: true`, a fresh `provisioned_at`, and
   an `inform_url` pointing at the controller. Note that once adoption
   completes the controller pushes the managed config, so the default
   `ubnt`/`ubnt` SSH login stops working (and the SSH host key changes) — that
   lockout is itself a sign adoption succeeded.

### How `get-device-authkey.sh` works

The controller image ships only `mongod` (no `mongo`/`mongosh` shell), and Mongo
binds to the pod's loopback, so the script `kubectl port-forward`s `27117` (which
reaches the pod loopback) and queries it with `pymongo<4` via `uv` — modern
pymongo refuses to talk to the ancient MongoDB 3.6 the controller bundles.

Requires `kubectl` (pointed at the cluster) and `uv`.

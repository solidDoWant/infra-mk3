// Builds the bridge's peer list from the vault databases on the CouchDB server, then runs
// the upstream bridge (main.ts) with it. Every database whose name starts with
// VAULT_PREFIX gets a couchdb peer and a one-way storage peer at VAULTS_DIR/<database>/.
// When the set of vault databases changes the process exits, so that the container
// restart picks up the new list.

const env = (name: string, fallback?: string): string => {
    const value = Deno.env.get(name) ?? fallback;
    if (value === undefined || value === "") {
        console.error(`[discover] ${name} must be set`);
        Deno.exit(1);
    }
    return value;
};

const couchdbUrl = env("COUCHDB_URL").replace(/\/+$/, "");
// _all_dbs is admin-only on CouchDB 3.x (and couchgres).
const adminUser = env("COUCHDB_ADMIN_USER");
const adminPassword = env("COUCHDB_ADMIN_PASSWORD");
const syncUser = env("COUCHDB_USER");
const syncPassword = env("COUCHDB_PASSWORD");
const vaultPrefix = env("VAULT_PREFIX", "vault-");
const passphrase = env("VAULT_PASSPHRASE");
const obfuscatePassphrase = Deno.env.get("VAULT_OBFUSCATE_PASSPHRASE") ?? passphrase;
const idDerivationKey = Deno.env.get("VAULT_ID_RECOVERY_CODE") ?? "";
const vaultsDir = env("VAULTS_DIR", "/vaults").replace(/\/+$/, "");
const configFile = env("LSB_CONFIG", "/tmp/config.json");
const pollSeconds = Number(env("DISCOVERY_INTERVAL_SECONDS", "60"));

const listVaults = async (): Promise<string[]> => {
    const response = await fetch(`${couchdbUrl}/_all_dbs`, {
        headers: { Authorization: `Basic ${btoa(`${adminUser}:${adminPassword}`)}` },
    });
    if (!response.ok) {
        throw new Error(`_all_dbs returned ${response.status}: ${await response.text()}`);
    }
    const databases: string[] = await response.json();
    return databases.filter((name) => name.startsWith(vaultPrefix)).sort();
};

const buildConfig = (vaults: string[]) => ({
    peers: vaults.flatMap((database) => [
        {
            type: "couchdb",
            name: `couchdb-${database}`,
            group: database,
            url: couchdbUrl,
            database,
            username: syncUser,
            password: syncPassword,
            passphrase,
            obfuscatePassphrase,
            ...(idDerivationKey ? { idDerivationKey } : {}),
            baseDir: "",
            useRemoteTweaks: true,
        },
        {
            type: "storage",
            name: `storage-${database}`,
            group: database,
            baseDir: `${vaultsDir}/${database}/`,
            // One-way copy: never send local changes back to the vault.
            ignore: ["**"],
            scanOfflineChanges: false,
        },
    ]),
});

let vaults: string[];
try {
    vaults = await listVaults();
} catch (e) {
    console.error("[discover] could not list vault databases:", e);
    Deno.exit(1);
}
console.log(`[discover] mirroring ${vaults.length} vault(s): ${vaults.join(", ") || "(none)"}`);
for (const database of vaults) {
    await Deno.mkdir(`${vaultsDir}/${database}`, { recursive: true });
}
await Deno.writeTextFile(configFile, JSON.stringify(buildConfig(vaults)), { mode: 0o600 });
Deno.env.set("LSB_CONFIG", configFile);

setInterval(async () => {
    try {
        const current = await listVaults();
        if (current.join("\n") !== vaults.join("\n")) {
            console.log(`[discover] vault list changed to: ${current.join(", ") || "(none)"}; restarting`);
            Deno.exit(0);
        }
    } catch (e) {
        // Server unavailability is the bridge's own problem to report; keep the current list.
        console.error("[discover] could not list vault databases:", e);
    }
}, pollSeconds * 1000);

await import("./main.ts");

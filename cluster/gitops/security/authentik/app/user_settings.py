from authentik.lib.CONFIG import __CONFIG


DATABASES = {
    "default": {
        "ENGINE": "authentik.root.db",
        "HOST": __CONFIG.get("postgresql.host"),
        "NAME": __CONFIG.get("postgresql.name"),
        "USER": __CONFIG.get("postgresql.user"),
        "PASSWORD": __CONFIG.get("postgresql.password"),
        "PORT": __CONFIG.get("postgresql.port"),
        # Diff: Move these under `OPTIONS` key where they belong
        "OPTIONS": {
            "sslmode": __CONFIG.get("postgresql.sslmode"),
            "sslcert": __CONFIG.get("postgresql.sslrootcert"),
            "sslrootcert": __CONFIG.get("postgresql.sslcert"),
            "sslkey": __CONFIG.get("postgresql.sslkey"),
        },
        "TEST": {
            "NAME": __CONFIG.get("postgresql.test.name"),
        },
    }
}

if __CONFIG.get_bool("postgresql.use_pgpool", False):
    DATABASES["default"]["DISABLE_SERVER_SIDE_CURSORS"] = True

if __CONFIG.get_bool("postgresql.use_pgbouncer", False):
    # https://docs.djangoproject.com/en/4.0/ref/databases/#transaction-pooling-server-side-cursors
    DATABASES["default"]["DISABLE_SERVER_SIDE_CURSORS"] = True
    # https://docs.djangoproject.com/en/4.0/ref/databases/#persistent-connections
    DATABASES["default"]["CONN_MAX_AGE"] = None  # persistent

for replica in __CONFIG.get_keys("postgresql.read_replicas"):
    _database = DATABASES["default"].copy()
    for setting in DATABASES["default"].keys():
        default = object()
        if setting in ("TEST",):
            continue
        override = __CONFIG.get(
            f"postgresql.read_replicas.{replica}.{setting.lower()}", default=default
        )
        if override is not default:
            _database[setting] = override
    DATABASES[f"replica_{replica}"] = _database

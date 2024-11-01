# Kubernetes resource labels

The following labels are used across multiple applications in the cluster:

| Key prefix               | Key name                      | Values  | Valid resources        | Required | Description                                                                                       |
| ------------------------ | ----------------------------- | ------- | ---------------------- | -------- | ------------------------------------------------------------------------------------------------- |
| `app.kubernetes.io`      | `name`                        | String  | Workloads and Networks | Yes      | Name of the app a resource belongs to. Used for network policy rules.                             |

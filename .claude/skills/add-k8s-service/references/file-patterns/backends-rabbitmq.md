# Backend — RabbitMQ

> **Flag before proceeding**: RabbitMQ setup involves enough raw CRDs and certificate infrastructure that it should ideally be wrapped in a dedicated chart (similar to `cluster/charts/postgres/` and `cluster/charts/dragonfly/`) rather than deployed as inline resources per-service. When a new application needs RabbitMQ, raise this with the user and confirm whether to proceed with raw CRDs or create a chart first.

RabbitMQ clusters require dedicated certificate infrastructure: a self-signed client CA (for mTLS auth), and a serving cert issued by the namespace intermediary CA. All connections use mTLS with x509 client authentication (no password auth).

RabbitMQ is complex — look at `cluster/gitops/media/kyoo/external-services/shared/rabbitmq/` as the reference implementation.

## shared/rabbitmq/auth/ — Certificate infrastructure (create once per cluster)

**auth/client-ca-cert.yaml** — Self-signed CA for client authentication:
```yaml
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: <service>-rabbitmq-auth-ca
spec:
  isCA: true
  commonName: <service> RabbitMQ authentication Certificate Authority
  subject:
    countries: [US]
    organizations: [infra-mk3]
    provinces: ["${SECRET_STATE}"]
  usages:
    - cert sign
    - crl sign
  nameConstraints:
    critical: true
    excluded:         # Exclude everything — only CN may be set for client certs
      dnsDomains: []
      ipRanges: []
      emailAddresses: []
      uriDomains: []
  duration: 87660h  # 10 years — this CA is rotated infrequently
  privateKey:
    algorithm: Ed25519
    encoding: PKCS8
    rotationPolicy: Never
  issuerRef:
    group: cert-manager.io
    kind: ClusterIssuer
    name: self-signed
  secretName: <service>-rabbitmq-auth-ca
```

**auth/client-ca-issuer.yaml**:
```yaml
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: <service>-rabbitmq-auth-ca
spec:
  ca:
    secretName: <service>-rabbitmq-auth-ca
```

**auth/serving-cert.yaml** — Server TLS cert (issued by namespace CA, ECDSA required):
```yaml
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: <service>-rabbitmq-serving-cert
spec:
  commonName: <service>-rabbitmq
  dnsNames:
    - <service>-rabbitmq.<namespace>.svc
    - <service>-rabbitmq.<namespace>.svc.cluster.local
    - "*.<service>-rabbitmq-nodes.<namespace>.svc"
    - "*.<service>-rabbitmq-nodes.<namespace>.svc.cluster.local"
  subject:
    countries: [US]
    organizations: [infra-mk3]
    provinces: ["${SECRET_STATE}"]
  usages:
    - server auth
  duration: 1h
  privateKey:
    algorithm: ECDSA   # RabbitMQ requires ECDSA for serving certs
    size: 384
    encoding: PKCS8
    rotationPolicy: Always
  issuerRef:
    group: cert-manager.io
    kind: Issuer
    name: <namespace>-intermediary-ca
  secretName: <service>-rabbitmq-serving-cert
```

**auth/serving-cert-crp.yaml** — Approve serving cert requests:
```yaml
---
apiVersion: policy.cert-manager.io/v1alpha1
kind: CertificateRequestPolicy
metadata:
  name: <namespace>-intermediary-ca-<service>-rabbitmq-serving-cert
spec:
  selector:
    issuerRef:
      group: cert-manager.io
      kind: Issuer
      name: <namespace>-intermediary-ca
    namespace:
      matchNames:
        - <namespace>
  allowed:
    commonName:
      required: true
      value: <service>-rabbitmq
    dnsNames:
      required: true
      values:
        - <service>-rabbitmq.<namespace>.svc
        - <service>-rabbitmq.<namespace>.svc.cluster.local
        - "*.<service>-rabbitmq-nodes.<namespace>.svc"
        - "*.<service>-rabbitmq-nodes.<namespace>.svc.cluster.local"
    subject:
      countries:
        required: true
        values: [US]
      organizations:
        required: true
        values: [infra-mk3]
      provinces:
        required: true
        values: ["${SECRET_STATE}"]
    usages:
      - server auth
  constraints:
    maxDuration: 1h
```

## shared/rabbitmq/rabbitmq-cluster.yaml

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/rabbitmq.com/rabbitmqcluster_v1beta1.json
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: <service>-rabbitmq
spec:
  replicas: 3    # Must be 1, 3, or 5. Use 3 for HA quorum.
  persistence:
    storageClassName: rabbitmq-default
    storage: 10Gi
  tls:
    # disableNonTLSListeners: true  # Enables TLS-only, but blocks plain HTTP metrics endpoint
    secretName: <service>-rabbitmq-serving-cert
    caSecretName: <service>-rabbitmq-auth-ca
  rabbitmq:
    additionalPlugins:
      - rabbitmq_auth_mechanism_ssl   # Enables x509 client cert authentication
    additionalConfig: |
      # Enforce mTLS — reject connections without a valid client certificate
      ssl_options.fail_if_no_peer_cert = true
      ssl_options.verify = verify_peer
      # Use EXTERNAL (x509) as the auth mechanism
      auth_mechanisms.1 = EXTERNAL
  override:
    service:
      metadata:
        labels:
          app.kubernetes.io/name: <service>-rabbitmq
          app.kubernetes.io/component: rabbitmq
          app.kubernetes.io/part-of: rabbitmq
          metrics: "true"   # Needed to distinguish main service from headless service
    statefulSet:
      spec:
        template:
          spec:
            containers: []  # Required by spec; meaningless here
            topologySpreadConstraints:
              - maxSkew: 1
                topologyKey: kubernetes.io/hostname
                whenUnsatisfiable: DoNotSchedule
                labelSelector:
                  matchLabels:
                    app.kubernetes.io/name: <service>-rabbitmq
                    app.kubernetes.io/component: rabbitmq
                    app.kubernetes.io/part-of: rabbitmq
```

## shared/rabbitmq/pdb.yaml

PDB requires `minAvailable: 2` to maintain quorum (majority of 3 nodes = 2):
```yaml
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: <service>-rabbitmq
  labels: &labels
    app.kubernetes.io/name: <service>-rabbitmq
    app.kubernetes.io/component: rabbitmq
    app.kubernetes.io/part-of: rabbitmq
spec:
  minAvailable: 2   # Must keep quorum — always 2 for a 3-node cluster
  selector:
    matchLabels: *labels
```

## shared/rabbitmq/rabbitmq-vhost.yaml

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/rabbitmq.com/vhost_v1beta1.json
apiVersion: rabbitmq.com/v1beta1
kind: Vhost
metadata:
  name: <service>-rabbitmq
spec:
  name: /<service>
  rabbitmqClusterReference:
    name: <service>-rabbitmq
```

## Per-consumer: user + permissions + client cert

**backend/rabbitmq/user-credentials.yaml** (no SOPS needed — no secret value):
```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: <service>-rabbitmq-<consumer>-credentials
type: Opaque
stringData:
  # CN= prefix tells the operator to match on the certificate CN field
  username: CN=<consumer>
  # Empty password — passwordless x509-only auth
  password: ""
```

**backend/rabbitmq/user.yaml**:
```yaml
---
apiVersion: rabbitmq.com/v1beta1
kind: User
metadata:
  name: <service>-rabbitmq-<consumer>
spec:
  importCredentialsSecret:
    name: <service>-rabbitmq-<consumer>-credentials
  rabbitmqClusterReference:
    name: <service>-rabbitmq
```

**backend/rabbitmq/permissions.yaml**:
```yaml
---
apiVersion: rabbitmq.com/v1beta1
kind: Permission
metadata:
  name: <service>-rabbitmq-<consumer>
spec:
  vhost: /<service>
  permissions:
    write: ".*"
    configure: ".*"
    read: ".*"
  userReference:
    name: <service>-rabbitmq-<consumer>
  rabbitmqClusterReference:
    name: <service>-rabbitmq
```

**backend/rabbitmq/user-certificate.yaml**:
```yaml
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: <service>-rabbitmq-<consumer>
spec:
  secretName: <service>-rabbitmq-<consumer>
  usages:
    - client auth
  commonName: <consumer>    # Must match the CN= value in user-credentials.yaml
  duration: 1h
  secretTemplate:
    labels:
      cnpg.io/reload: "true"
  issuerRef:
    group: cert-manager.io
    kind: Issuer
    name: <service>-rabbitmq-auth-ca
```

**backend/rabbitmq/user-crp.yaml**:
```yaml
---
apiVersion: policy.cert-manager.io/v1alpha1
kind: CertificateRequestPolicy
metadata:
  name: <service>-rabbitmq-auth-ca-<consumer>
spec:
  selector:
    issuerRef:
      group: cert-manager.io
      kind: Issuer
      name: <service>-rabbitmq-auth-ca
    namespace:
      matchNames:
        - <namespace>
  allowed:
    commonName:
      required: true
      value: <consumer>
    usages:
      - client auth
  constraints:
    maxDuration: 1h
```

## Optional topology resources (Exchange, Queue, Binding)

If the application requires specific exchanges, queues, or bindings, create them as topology operator CRDs. Use `type: quorum` for queues to survive node failures. See `cluster/gitops/media/kyoo/external-services/shared/rabbitmq/` for examples.

# Backend — S3 Object Storage (Rook Ceph)

## backend/s3/bucketclaim.yaml

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/objectbucket.io/objectbucketclaim_v1alpha1.json
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: &name <service>-bucket
spec:
  generateBucketName: *name
  storageClassName: ssd-replicated-object
  additionalConfig:
    maxObjects: "10000"
    maxSize: 100G
```

## backend/s3/build-s3-config-policy.yaml — Kyverno transformation (always needed)

When the ObjectBucketClaim is provisioned, Rook creates a ConfigMap and Secret with raw keys (`BUCKET_HOST`, `BUCKET_PORT`, `BUCKET_NAME`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`). Most applications expect these in a different format, and the S3 endpoint must always be explicitly constructed (not assumed).

Use a Kyverno `Policy` to transform the OBC-generated resources into what the app needs:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/kyverno.io/policy_v1.json
apiVersion: kyverno.io/v1
kind: Policy
metadata:
  name: build-<service>-bucket-config
spec:
  rules:
    # Transform the credentials Secret into app-specific key names
    - name: build-<service>-bucket-credentials
      match:
        any:
          - resources:
              kinds:
                - Secret
              name: <service>-bucket
      skipBackgroundRequests: true
      generate:
        generateExisting: true
        synchronize: true
        apiVersion: v1
        kind: Secret
        name: <service>-bucket-credentials
        namespace: <namespace>
        data:
          data:
            # Rename to whatever env var names the app expects:
            S3_ACCESS_KEY: "{{ request.object.data.AWS_ACCESS_KEY_ID }}"
            S3_SECRET_KEY: "{{ request.object.data.AWS_SECRET_ACCESS_KEY }}"

    # Construct the full S3 endpoint URL from bucket host + port.
    # The bucket name has a random suffix so it can't be hardcoded.
    - name: build-<service>-bucket-config
      match:
        any:
          - resources:
              kinds:
                - ConfigMap
              name: <service>-bucket
      skipBackgroundRequests: true
      generate:
        generateExisting: true
        synchronize: true
        apiVersion: v1
        kind: ConfigMap
        name: <service>-bucket-config
        namespace: <namespace>
        data:
          data:
            # Always construct the endpoint explicitly — never assume a default
            S3_ENDPOINT: "https://{{ request.object.data.BUCKET_HOST }}:{{ request.object.data.BUCKET_PORT }}"
            S3_BUCKET: "{{ request.object.data.BUCKET_NAME }}"
            S3_REGION: "{{ request.object.data.BUCKET_REGION }}"
```

Then reference the generated resources in the HelmRelease:
```yaml
envFrom:
  - secretRef:
      name: <service>-bucket-credentials
  - configMapRef:
      name: <service>-bucket-config
```

**Why Kyverno?** The bucket name includes a random suffix generated at provision time, so the endpoint URL and bucket name can't be known ahead of time. The Kyverno policy watches the OBC ConfigMap/Secret and regenerates the transformed versions whenever they change.

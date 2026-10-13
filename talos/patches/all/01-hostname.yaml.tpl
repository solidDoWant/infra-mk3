---
# yaml-language-server: $schema=https://docs.siderolabs.com/talos/v1.14/schemas/config.schema.json
apiVersion: v1alpha1
kind: HostnameConfig
auto: "off"
hostname: "{{ .Node.Host }}"

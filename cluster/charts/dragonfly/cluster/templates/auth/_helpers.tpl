{{/* Define common values */}}
{{- define "auth.ca-cert-name" -}}
{{- include "cluster-resource-name" . -}}-auth-ca
{{- end }}

{{- define "auth.ca-issuer-ref" -}}
group: cert-manager.io
kind: Issuer
name: {{ include "auth.ca-cert-name" . }}
{{- end }}

{{- define "auth.ca-secret-generator-policy-name" -}}
extract-{{- include "cluster-resource-name" . -}}-auth-ca-certificate
{{- end }}

{{- define "auth.ca-secret-name" -}}
{{- include "cluster-resource-name" . -}}-client-auth-public-certs
{{- end }}

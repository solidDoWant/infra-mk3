{{/* Define common values */}}
{{- define "cnpg-labels" -}}
labels:
  cnpg.io/reload: "true"
{{- end }}

{{- define "ca-cert-name" -}}
{{ .Values.clusterName }}-postgres-auth-ca
{{- end }}

{{- define "ca-issuer-ref" -}}
group: cert-manager.io
kind: Issuer
name: {{ include "ca-cert-name" . }}
{{- end }}

{{- define "ca-secret-generator-policy-name" -}}
extract-{{ .Values.clusterName }}-postgres-auth-ca-certificate
{{- end }}

{{- define "ca-secret-name" -}}
{{ .Values.clusterName }}-client-auth-public-certs
{{- end }}

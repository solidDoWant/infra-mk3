{{/* Define common values */}}
{{- define "cnpg-labels" -}}
labels:
  cnpg.io/reload: "true"
{{- end }}

{{- define "ca-cert-name" -}}
{{ .Values.serviceName }}-postgres-auth-ca
{{- end }}

{{- define "ca-issuer-ref" -}}
group: cert-manager.io
kind: Issuer
name: {{ include "ca-cert-name" . }}
{{- end }}

{{- define "ca-secret-generator-policy-name" -}}
extract-{{ .Values.serviceName }}-postgres-auth-ca-certificate
{{- end }}

{{- define "ca-secret-name" -}}
{{ .Values.serviceName }}-client-auth-public-certs
{{- end }}

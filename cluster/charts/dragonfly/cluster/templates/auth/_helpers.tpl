{{/* Define common values */}}
{{- define "auth.ca-cert-name" -}}
{{ .Values.serviceName }}-dragonfly-auth-ca
{{- end }}

{{- define "auth.ca-issuer-ref" -}}
group: cert-manager.io
kind: Issuer
name: {{ include "auth.ca-cert-name" . }}
{{- end }}

{{- define "auth.ca-secret-generator-policy-name" -}}
extract-{{ .Values.serviceName }}-dragonfly-auth-ca-certificate
{{- end }}

{{- define "auth.ca-secret-name" -}}
{{ .Values.serviceName }}-client-auth-public-certs
{{- end }}

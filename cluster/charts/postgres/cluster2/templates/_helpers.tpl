{{- define "cluster-resource-name" -}}
{{ .Values.clusterName }}-postgres
{{- end -}}

{{- define "cluster-readable-name" -}}
{{ .Values.clusterName }}-postgres
{{- end -}}

{{- define "serving-cert-name" -}}
{{ include "cluster-resource-name" . }}-serving-cert
{{- end -}}

{{/*
    The service name itself is not included here because my intermediary namespace
    certs have constraints on them that require leaf certs to include the namespace.
*/}}
{{- define "serving-domain-names" -}}
- {{ include "cluster-resource-name" . }}-rw.{{ .Release.Namespace }}.svc
- {{ include "cluster-resource-name" . }}-ro.{{ .Release.Namespace }}.svc
- {{ include "cluster-resource-name" . }}-r.{{ .Release.Namespace }}.svc
- {{ include "cluster-resource-name" . }}-rw.{{ .Release.Namespace }}.svc.cluster.local
- {{ include "cluster-resource-name" . }}-ro.{{ .Release.Namespace }}.svc.cluster.local
- {{ include "cluster-resource-name" . }}-r.{{ .Release.Namespace }}.svc.cluster.local
{{- end -}}

{{- define "wal-bucket-name" -}}
{{ include "cluster-resource-name" . }}-wal
{{- end -}}

{{- define "db-registration-configmap-name" -}}
{{ include "cluster-resource-name" .}}-db-registration
{{- end }}

{{- define "bucket.port" -}}
{{- if .Values.bucket.endpoint -}}
{{ default 443 (regexSplit ":" (urlParse .Values.bucket.endpoint).host 2 | rest | first) | quote }}
{{- end -}}
{{- end -}}

{{- define "pooler-rw-name" -}}
{{ include "cluster-resource-name" . }}-pooler-rw
{{- end -}}

{{- define "pooler-ro-name" -}}
{{ include "cluster-resource-name" . }}-pooler-ro
{{- end -}}

{{- define "pooler-rw-serving-cert-name" -}}
{{ include "pooler-rw-name" . }}-serving-cert
{{- end -}}

{{- define "pooler-ro-serving-cert-name" -}}
{{ include "pooler-ro-name" . }}-serving-cert
{{- end -}}

{{/*
    Same rule as serving-domain-names: namespace must be included in the SAN.
*/}}
{{- define "pooler-rw-serving-domain-names" -}}
- {{ include "pooler-rw-name" . }}.{{ .Release.Namespace }}.svc
- {{ include "pooler-rw-name" . }}.{{ .Release.Namespace }}.svc.cluster.local
{{- end -}}

{{- define "pooler-ro-serving-domain-names" -}}
- {{ include "pooler-ro-name" . }}.{{ .Release.Namespace }}.svc
- {{ include "pooler-ro-name" . }}.{{ .Release.Namespace }}.svc.cluster.local
{{- end -}}

{{- define "cnpg-labels" -}}
labels:
  cnpg.io/reload: "true"
{{- end }}

{{- define "ca-cert-name" -}}
{{ .Values.clusterName }}-postgres-auth-ca
{{- end -}}

{{- define "ca-issuer-ref" -}}
group: cert-manager.io
kind: Issuer
name: {{ include "ca-cert-name" . }}
{{- end -}}

{{- define "ca-secret-generator-policy-name" -}}
extract-{{ .Values.clusterName }}-postgres-auth-ca-certificate
{{- end -}}

{{- define "ca-secret-name" -}}
{{ .Values.clusterName }}-client-auth-public-certs
{{- end -}}

{{- define "streaming-replica-cert-name" -}}
{{ .Values.clusterName }}-postgres-streaming-replica-user
{{- end -}}

{{- define "pooler-cert-name" -}}
{{ .Values.clusterName }}-postgres-pooler-user
{{- end -}}

{{- define "cluster-resource-name" -}}
{{ .Values.clusterName }}-postgres-{{ .Values.majorVersion }}
{{- end -}}

{{- define "cluster-readable-name" -}}
{{ .Values.clusterName }}-postgres-{{ .Values.majorVersion }}
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

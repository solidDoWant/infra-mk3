{{- define "cluster-resource-name" -}}
{{ .Values.clusterName }}-postgres-{{ .Values.majorVersion }}
{{- end -}}

{{- define "serving-cert-name" -}}
{{ include "cluster-resource-name" . }}-serving-cert
{{- end -}}

{{- define "serving-cert-common-name" -}}
{{ .Values.clusterName }} Postgres {{ .Values.majorVersion }}
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

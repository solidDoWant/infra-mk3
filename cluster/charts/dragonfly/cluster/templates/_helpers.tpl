{{- define "cluster-resource-name" -}}
{{ .Values.serviceName }}-dragonfly
{{- end -}}

{{- define "cluster-readable-name" -}}
{{ .Values.serviceName }}-dragonfly
{{- end -}}

{{- define "serving-cert-name" -}}
{{ include "cluster-resource-name" . }}-serving-cert
{{- end -}}

{{/*
    The service name itself is not included here because my intermediary namespace
    certs have constraints on them that require leaf certs to include the namespace.
*/}}
{{- define "serving-domain-names" -}}
- {{ include "cluster-resource-name" . }}.{{ .Release.Namespace }}.svc
- {{ include "cluster-resource-name" . }}.{{ .Release.Namespace }}.svc.cluster.local
{{- end -}}

{{- define "secret-labels" -}}
labels:
  kyverno.home.arpa/reload: "true"
{{- end }}

{{- define "db-registration-configmap-name" -}}
{{ include "cluster-resource-name" .}}-db-registration
{{- end }}

{{- define "pod-selector-labels" -}}
app.kubernetes.io/name: dragonfly
app.kubernetes.io/instance: {{ include "cluster-resource-name" . }}
{{- end}}

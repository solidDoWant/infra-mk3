{{- define "ci-project.namespace" -}}
ci-{{ required "name is required" .Values.name }}
{{- end -}}

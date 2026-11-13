{{- define "kunde.name" -}}kunde-backend-{{ required "cell.id is required" .Values.cell.id }}{{- end -}}
{{- define "kunde.image" -}}
{{- $repo := required "image.repository is required" .Values.image.repository -}}
{{- if .Values.image.digest -}}{{ $repo }}@{{ .Values.image.digest }}
{{- else -}}{{ $repo }}:{{ required "image.digest or image.tag is required" .Values.image.tag }}{{- end -}}
{{- end -}}
{{- define "kunde.labels" -}}
app.kubernetes.io/name: kunde-backend
app.kubernetes.io/instance: {{ include "kunde.name" . }}
kunde.kz/country: {{ required "cell.country is required" .Values.cell.country | quote }}
{{- end -}}

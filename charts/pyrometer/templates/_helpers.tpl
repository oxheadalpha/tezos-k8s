{{/*
Expand the name of the chart.
*/}}
{{- define "pyrometer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "pyrometer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pyrometer.labels" -}}
helm.sh/chart: {{ include "pyrometer.chart" . }}
{{ include "pyrometer.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pyrometer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pyrometer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "tacoinfra-remote-signer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "tacoinfra-remote-signer.labels" -}}
helm.sh/chart: {{ include "tacoinfra-remote-signer.chart" . }}
{{ include "tacoinfra-remote-signer.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "tacoinfra-remote-signer.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

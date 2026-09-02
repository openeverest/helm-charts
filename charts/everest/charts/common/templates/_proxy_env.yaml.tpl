#
# @param .httpProxy     HTTP proxy URL. Renders nothing if empty.
# @param .httpsProxy    HTTPS proxy URL. Renders nothing if empty.
# @param .noProxy       Comma-separated no-proxy list. Renders nothing if empty.
#
{{/* Proxy environment variables. Renders nothing when no proxy is configured. */}}
{{- define "everest.proxyEnv" -}}
{{- with .httpProxy }}
- name: HTTP_PROXY
  value: {{ . | quote }}
{{- end }}
{{- with .httpsProxy }}
- name: HTTPS_PROXY
  value: {{ . | quote }}
{{- end }}
{{- with .noProxy }}
- name: NO_PROXY
  value: {{ . | quote }}
{{- end }}
{{- end }}

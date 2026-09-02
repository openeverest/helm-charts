#
# @param .namespace             The namespace where the operator is installed
# @param .version               Version to upgrade to
# @param .versionMetadataURL    The URL of the version metadata service
# @param .image                 The image to use for running the hook Job
# @param .global                Global values, e.g. httpProxy/httpsProxy/noProxy
#
{{- define "everest.preUpgradeChecks" }}
{{- $hookName := printf "everest-helm-pre-upgrade-hook" }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ $hookName }}
  namespace: {{ .namespace }}
  annotations:
    "helm.sh/hook": pre-upgrade
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ $hookName }}
  namespace: {{ .namespace }}
  annotations:
    "helm.sh/hook": pre-upgrade
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
rules:
  - apiGroups:
      - apps
    resources:
      - deployments
    verbs:
      - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ $hookName }}
  namespace: {{ .namespace }}
  annotations:
    "helm.sh/hook": pre-upgrade
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ $hookName }}
subjects:
  - kind: ServiceAccount
    name: {{ $hookName }}
    namespace: {{ .namespace }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{ $hookName }}
  annotations:
    "helm.sh/hook": pre-upgrade
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
rules:
  - apiGroups:
      - ""
    resources:
      - namespaces
    verbs:
      - list
  - apiGroups:
      - operators.coreos.com
    resources:
      - subscriptions
      - clusterserviceversions
    verbs:
      - get
      - list
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ $hookName }}
  annotations:
    "helm.sh/hook": pre-upgrade
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ $hookName }}
subjects:
  - kind: ServiceAccount
    name: {{ $hookName }}
    namespace: {{ .namespace }}
---
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ $hookName }}-{{ randNumeric 6 }}
  namespace: {{ .namespace }}
  annotations:
    "helm.sh/hook": pre-upgrade
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  template:
    spec:
      containers:
        - image: {{ .image }}:{{ .version }}
          name: {{ $hookName }}
          command:
            - /bin/sh
            - -ec
            - |
              echo "Checking requirements for upgrade to version {{ .version }}"
              everestctl upgrade --in-cluster --dry-run --version-metadata-url={{ .versionMetadataURL }} --kubeconfig=""
          {{- with include "everest.proxyEnv" .global | trim }}
          env:
            {{- . | nindent 12 }}
          {{- end }}
      dnsPolicy: ClusterFirst
      restartPolicy: OnFailure
      terminationGracePeriodSeconds: 30
      serviceAccount: {{ $hookName }}
      serviceAccountName: {{ $hookName }}
{{- end }}

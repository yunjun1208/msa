apiVersion: v1
kind: ServiceAccount
metadata:
  name: alertmanager
  namespace: monitoring
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: alertmanager-config
  namespace: monitoring
data:
  alertmanager.yml: |
    global:
      resolve_timeout: 5m
    route:
      receiver: infra-sns
      group_by: ['alertname', 'namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
    receivers:
      - name: infra-sns
        sns_configs:
          - topic_arn: '__INFRA_SNS_TOPIC__'
            sigv4:
              region: '__REGION__'
            subject: 'EKS Infrastructure Alert'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager
  namespace: monitoring
spec:
  replicas: 1
  selector: {matchLabels: {app: alertmanager}}
  template:
    metadata: {labels: {app: alertmanager}}
    spec:
      serviceAccountName: alertmanager
      containers:
        - name: alertmanager
          image: prom/alertmanager:v0.28.1
          args: ['--config.file=/etc/alertmanager/alertmanager.yml']
          ports: [{containerPort: 9093}]
          resources:
            requests: {cpu: 50m, memory: 64Mi}
            limits: {cpu: 200m, memory: 256Mi}
          volumeMounts: [{name: config, mountPath: /etc/alertmanager}]
      volumes: [{name: config, configMap: {name: alertmanager-config}}]
---
apiVersion: v1
kind: Service
metadata:
  name: alertmanager
  namespace: monitoring
spec:
  ports: [{port: 9093, targetPort: 9093}]
  selector: {app: alertmanager}

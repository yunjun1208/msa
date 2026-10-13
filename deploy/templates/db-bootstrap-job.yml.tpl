apiVersion: batch/v1
kind: Job
metadata:
  name: msa-db-bootstrap
  namespace: soldesk
spec:
  ttlSecondsAfterFinished: 1800
  activeDeadlineSeconds: 330
  backoffLimit: 2
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: mysql
          image: mysql:8.4
          command: ['/bin/sh','-c']
          args: ['export MYSQL_PWD="$DB_ADMIN_PASSWORD"; mysql --ssl-mode=REQUIRED -h "$DB_HOST" -u admin < /bootstrap/init.sql']
          env:
            - name: DB_HOST
              valueFrom:
                secretKeyRef: {name: my-app-secrets, key: DB_HOST}
            - name: DB_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef: {name: my-app-secrets, key: DB_PW}
          volumeMounts:
            - {name: init, mountPath: /bootstrap, readOnly: true}
      volumes:
        - name: init
          secret:
            secretName: msa-bootstrap-sql

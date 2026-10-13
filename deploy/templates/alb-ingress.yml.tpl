# Rendered by scripts/02-configure-repo.ps1. Commit the generated manifest to Git.
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: msa-public-alb
  namespace: soldesk
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/certificate-arn: __ACM_ARN__
    alb.ingress.kubernetes.io/group.name: msa-public
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '30'
    alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=120
    external-dns.alpha.kubernetes.io/hostname: __SITE_DOMAIN__
spec:
  ingressClassName: alb
  rules:
    - host: __SITE_DOMAIN__
      http:
        paths:
          - path: /member-service
            pathType: Prefix
            backend:
              service:
                name: apigateway-service
                port: {number: 80}
          - path: /product-service
            pathType: Prefix
            backend:
              service:
                name: apigateway-service
                port: {number: 80}
          - path: /ordering-service
            pathType: Prefix
            backend:
              service:
                name: apigateway-service
                port: {number: 80}
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-service
                port: {number: 80}

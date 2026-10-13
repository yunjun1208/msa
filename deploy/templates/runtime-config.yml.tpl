apiVersion: v1
kind: ConfigMap
metadata:
  name: msa-runtime-config
  namespace: soldesk
data:
  PRODUCT_IMAGE_BUCKET: '__PRODUCT_IMAGE_BUCKET__'
  ORDER_EVENTS_TOPIC_ARN: '__ORDER_EVENTS_TOPIC_ARN__'

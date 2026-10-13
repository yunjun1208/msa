package com.example.ordersystem.ordering.service;

import com.example.ordersystem.ordering.domain.Ordering;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.http.*;
import org.springframework.web.client.RestTemplate;
import java.util.Map;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.model.PublishRequest;

@Component
public class OrderEventPublisher {
    private static final Logger log = LoggerFactory.getLogger(OrderEventPublisher.class);
    private final String topicArn;
    private final boolean enabled;
    private final SnsClient snsClient;
    private final RestTemplate restTemplate;
    private final String internalServiceToken;

    public OrderEventPublisher(
            @Value("${app.order-events.topic-arn:}") String topicArn,
            @Value("${app.order-events.enabled:false}") boolean enabled,
            @Value("${app.aws.region:ap-northeast-2}") String region,
            @Value("${internal.service-token}") String internalServiceToken,
            RestTemplate restTemplate) {
        this.topicArn = topicArn;
        this.restTemplate = restTemplate;
        this.internalServiceToken = internalServiceToken;
        this.enabled = enabled;
        // The default AWS credentials chain supports EKS Pod Identity.
        this.snsClient = enabled ? SnsClient.builder().region(Region.of(region)).build() : null;
        if (enabled && (topicArn == null || topicArn.isBlank())) {
            throw new IllegalStateException("ORDER_EVENTS_TOPIC_ARN is required when events are enabled");
        }
    }

    public void publishAfterCommit(Ordering order) {
        if (!enabled) return;
        long orderId = order.getId();
        long memberId = order.getMemberId();
        long productId = order.getProductId();
        int quantity = order.getQuantity();
        // The email lookup happens after commit; we do not expose this endpoint via ALB.
        Runnable publisher = () -> {
            try {
                HttpHeaders headers = new HttpHeaders();
                headers.set("X-Internal-Token", internalServiceToken);
                ResponseEntity<Map> emailResponse = restTemplate.exchange(
                        "http://member-service/member/internal/email/" + memberId,
                        HttpMethod.GET, new HttpEntity<>(headers), Map.class);
                Object emailObject = emailResponse.getBody() == null ? null : emailResponse.getBody().get("email");
                if (!(emailObject instanceof String email) || email.isBlank()) {
                    throw new IllegalStateException("No recipient email for order=" + orderId);
                }
                // Email goes only to SNS/SQS; never print addresses to logs.
                String safeEmail = email.replace("\\", "\\\\").replace("\"", "\\\"");
                String message = String.format(
                        "{\"eventType\":\"ORDER_CREATED\",\"orderId\":%d,\"memberId\":%d,\"productId\":%d,\"quantity\":%d,\"recipientEmail\":\"%s\"}",
                        orderId, memberId, productId, quantity, safeEmail);
                snsClient.publish(PublishRequest.builder()
                        .topicArn(topicArn).message(message)
                        .messageAttributes(java.util.Map.of("eventType",
                                software.amazon.awssdk.services.sns.model.MessageAttributeValue.builder()
                                        .dataType("String").stringValue("ORDER_CREATED").build()))
                        .build());
                log.info("Order event published: orderId={}", orderId);
            } catch (Exception e) {
                // Demo-level post-commit delivery: errors require monitoring/retry.
                // Production-grade reliability needs the transactional outbox pattern.
                log.error("Order event publish FAILED after DB commit: orderId={}", orderId, e);
            }
        };
        if (TransactionSynchronizationManager.isSynchronizationActive()
                && TransactionSynchronizationManager.isActualTransactionActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override public void afterCommit() { publisher.run(); }
            });
        } else {
            publisher.run();
        }
    }
}

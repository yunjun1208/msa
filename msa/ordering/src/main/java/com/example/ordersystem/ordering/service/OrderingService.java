package com.example.ordersystem.ordering.service;

import com.example.ordersystem.ordering.domain.Ordering;
import com.example.ordersystem.ordering.dto.OrderCreateDto;
import com.example.ordersystem.ordering.dto.ProductDto;
import com.example.ordersystem.ordering.dto.ProductUpdateStockDto;
import com.example.ordersystem.ordering.repository.OrderingRepository;
import jakarta.persistence.EntityNotFoundException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
@Transactional
public class OrderingService {
    private final OrderingRepository orderingRepository;
    private final ProductFeign productFeign;
    private final OrderEventPublisher eventPublisher;

    @Value("${internal.service-token}")
    private String internalServiceToken;

    public OrderingService(OrderingRepository orderingRepository,
                           ProductFeign productFeign,
                           OrderEventPublisher eventPublisher) {
        this.orderingRepository = orderingRepository;
        this.productFeign = productFeign;
        this.eventPublisher = eventPublisher;
    }

    // 주문 API에서 실제 사용 중인 Feign 기반 주문 생성 경로
    public Ordering orderFeignCreate(OrderCreateDto orderDto, String userId) {
        // 다른 서비스의 DB/재고를 변경하기 전에 요청값을 먼저 검증한다.
        long memberId = validateMemberId(userId);
        if (orderDto == null || orderDto.getProductId() == null
                || orderDto.getProductId() <= 0
                || orderDto.getProductCount() == null
                || orderDto.getProductCount() <= 0) {
            throw new IllegalArgumentException("유효한 상품 ID와 1개 이상의 구매 수량이 필요합니다.");
        }

        ProductDto product = productFeign.getProductById(orderDto.getProductId(), userId);
        if (product == null) {
            throw new EntityNotFoundException("없는 상품입니다.");
        }

        int quantity = orderDto.getProductCount();
        if (product.getStockQuantity() < quantity) {
            throw new IllegalArgumentException("재고 부족");
        }

        // 최종 재고 차감은 Product 서비스에서 검증한다.
        ProductUpdateStockDto stockDto = ProductUpdateStockDto.builder()
                .productId(orderDto.getProductId())
                .productQuantity(quantity)
                .build();
        productFeign.updateProductStock(stockDto, internalServiceToken);

        Ordering ordering = Ordering.builder()
                .memberId(memberId)
                .productId(orderDto.getProductId())
                .quantity(quantity)
                .build();
        orderingRepository.save(ordering);
        eventPublisher.publishAfterCommit(ordering);
        return ordering;
    }

    private long validateMemberId(String userId) {
        if (userId == null || userId.isBlank()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "로그인 사용자 정보가 없습니다.");
        }

        final long memberId;
        try {
            memberId = Long.parseLong(userId);
        } catch (NumberFormatException e) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "잘못된 사용자 ID입니다.");
        }
        if (memberId <= 0) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "유효하지 않은 사용자 ID입니다.");
        }
        return memberId;
    }
}

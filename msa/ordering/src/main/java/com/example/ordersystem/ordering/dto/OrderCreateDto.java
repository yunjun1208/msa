package com.example.ordersystem.ordering.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class OrderCreateDto {
    @NotNull(message = "상품 ID가 필요합니다.")
    @Positive(message = "상품 ID는 1 이상이어야 합니다.")
    private Long productId;

    @NotNull(message = "구매 수량이 필요합니다.")
    @Positive(message = "구매 수량은 1 이상이어야 합니다.")
    private Integer productCount;
}

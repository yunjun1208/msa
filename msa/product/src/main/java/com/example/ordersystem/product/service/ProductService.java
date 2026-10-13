package com.example.ordersystem.product.service;

import com.example.ordersystem.product.domain.Product;
import com.example.ordersystem.product.dto.ProductRegisterDto;
import com.example.ordersystem.product.dto.ProductResDto;
import com.example.ordersystem.product.dto.ProductUpdateStockDto;
import com.example.ordersystem.product.repository.ProductRepository;
import jakarta.persistence.EntityNotFoundException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.IOException;
import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

@Service
@Transactional
public class ProductService {
    private final ProductRepository productRepository;
    private final S3Service s3Service;

    public ProductService(ProductRepository productRepository, S3Service s3Service) {
        this.productRepository = productRepository;
        this.s3Service = s3Service;
    }

    public Product productCreate(ProductRegisterDto dto, String userId)
        throws IOException {

        // 1. 로그인 사용자 ID 필수 확인
        if (userId == null || userId.isBlank()) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED,
                    "로그인 사용자 정보가 없습니다."
            );
        }

        // 2. JWT에서 전달된 사용자 ID 형식 검증
        Long memberId;

        try {
            memberId = Long.parseLong(userId);
        } catch (NumberFormatException e) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED,
                    "잘못된 사용자 ID입니다."
            );
        }

        // 3. 유효한 사용자 ID인지 확인
        if (memberId <= 0) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED,
                    "유효하지 않은 사용자 ID입니다."
            );
        }

        // 4. 사용자 검증 후 S3 이미지 업로드
        String finalImageUrl = dto.getImageUrl();

        if (dto.getImageFile() != null
                && !dto.getImageFile().isEmpty()) {

            finalImageUrl =
                    s3Service.uploadFile(dto.getImageFile());
        }

        // 5. 로그인 사용자 ID로 상품 저장
        return productRepository.save(
                dto.toEntity(memberId, finalImageUrl)
        );
    }

    // 주문 서비스에서 호출하는 재고 차감 메서드
    public Product updateStockQuantity(ProductUpdateStockDto productUpdateStockDto) {
        Product product = productRepository.findById(productUpdateStockDto.getProductId())
                .orElseThrow(() -> new EntityNotFoundException("없는 상품입니다."));

        if (productUpdateStockDto.getProductQuantity() == null) {
            throw new IllegalArgumentException("구매 수량이 없습니다.");
        }

        product.updateStockQuantity(productUpdateStockDto.getProductQuantity());
        return product;
    }

    // 상품 상세 조회
    @Transactional(readOnly = true)
    public ProductResDto productDetail(Long id) {
        Product product = productRepository.findById(id)
                .orElseThrow(() -> new EntityNotFoundException("없는 상품입니다."));
        return toDto(product);
    }

    // 상품 목록 조회 (최신 등록순)
    @Transactional(readOnly = true)
    public List<ProductResDto> productList() {
        return productRepository.findAllByOrderByIdDesc()
                .stream()
                .map(this::toDto)
                .toList();
    }

    private ProductResDto toDto(Product product){
        return ProductResDto.builder()
                .id(product.getId())
                .name(product.getName())
                .category(product.getCategory())
                .description(product.getDescription())
                .imageUrl(product.getImageUrl())
                .price(product.getPrice())
                .stockQuantity(product.getStockQuantity())
                .build();
    }
}

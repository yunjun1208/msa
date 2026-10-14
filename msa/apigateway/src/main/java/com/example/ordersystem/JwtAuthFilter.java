package com.example.ordersystem;

import io.jsonwebtoken.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;
import org.springframework.core.Ordered;

@Component
public class JwtAuthFilter implements GlobalFilter, Ordered {

    @Value("${jwt.secretKey}")
    private String secretKey;

    @Override
    public int getOrder() {
        return -100;
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String bearerToken = exchange.getRequest().getHeaders().getFirst(HttpHeaders.AUTHORIZATION);
        String path = exchange.getRequest().getURI().getRawPath();
        HttpMethod method = exchange.getRequest().getMethod();

        if (path.matches(".*/product/(updatestock|[0-9]+/purchase)$") ||
                path.matches(".*/member/internal/.*")) {
            exchange.getResponse().setStatusCode(HttpStatus.FORBIDDEN);
            return exchange.getResponse().setComplete();
        }
        if (isPublicPath(path, method)) {

            // 외부 사용자가 전달한 신원 정보 헤더 제거
            ServerWebExchange safeExchange = exchange.mutate()
                    .request(builder -> builder.headers(headers -> {
                        headers.remove("X-User-Id");
                        headers.remove("X-User-Role");
                    }))
                    .build();
            return chain.filter(safeExchange);
        }

        try {
            if (bearerToken == null || !bearerToken.startsWith("Bearer ")) {
                throw new IllegalArgumentException("token 관련 예외 발생");
            }
            String token = bearerToken.substring(7);

            Claims claims = Jwts.parserBuilder()
                    .setSigningKey(secretKey)
                    .build()
                    .parseClaimsJws(token)
                    .getBody();

            String userId = claims.getSubject();
            String role = claims.get("role", String.class);

            if (userId == null || userId.isBlank()) {
                throw new IllegalArgumentException("JWT 사용자 ID가 없습니다.");
            }

            // Member 서비스에서 발급하는 역할만 허용
            if (!"USER".equals(role) && !"ADMIN".equals(role)) {
                throw new IllegalArgumentException("JWT Role 값이 올바르지 않습니다.");
            }

            ServerWebExchange modifiedExchange = exchange.mutate()
                    .request(builder -> builder
                            .headers(headers -> {
                                headers.remove("X-User-Id");
                                headers.remove("X-User-Role");
                                headers.set("X-User-Id", userId);
                                headers.set("X-User-Role", "ROLE_" + role);
                            })
                    )
                    .build();

            return chain.filter(modifiedExchange);
        } catch (JwtException | IllegalArgumentException e) {

            System.out.println("===== JWT AUTH ERROR =====");
            System.out.println("Exception: " + e.getClass().getName());
            System.out.println("Message: " + e.getMessage());

            exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
            return exchange.getResponse().setComplete();
        }
    }

    private boolean isPublicPath(String path, HttpMethod method) {

    // GET 요청: 상품 조회 및 서비스 상태 확인
    if (HttpMethod.GET.equals(method)) {
        return path.equals("/member-service/health")
                || path.equals("/product-service/health")
                || path.equals("/ordering-service/health")
                || path.equals("/product-service/product/list")
                || path.matches("^/product-service/product/[0-9]+$");
    }

    // POST 요청: 회원가입, 로그인, 토큰 재발급
    if (HttpMethod.POST.equals(method)) {
        return path.equals("/member-service/member/create")
                || path.equals("/member-service/member/doLogin")
                || path.equals("/member-service/member/refresh-token");
    }

    // 그 외 요청은 JWT 인증 필요
    return false;
}
}

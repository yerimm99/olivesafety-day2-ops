package org.olivesafety.order.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.olivesafety.order.domain.PayType;

import java.time.LocalDateTime;

public class OrdersResponseDTO {
    @Builder
    @Getter
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ordersAddResultDTO {
        Long ordersId;
        LocalDateTime createdAt;
    }

    @Builder
    @Getter
    @NoArgsConstructor
    @AllArgsConstructor
    public static class OrderMessageDTO {
        private String name;
        private String phone;
        private PayType payType;
        private Long memberId;
        private Long itemId;
        private Long amount;

    }

}

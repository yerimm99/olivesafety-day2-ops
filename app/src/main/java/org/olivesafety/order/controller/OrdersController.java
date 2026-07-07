package org.olivesafety.order.controller;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.olivesafety.common.exception.handler.MemberHandler;
import org.olivesafety.common.exception.status.ErrorStatus;
import org.olivesafety.common.exception.status.SuccessStatus;
import org.olivesafety.common.presentation.ApiResponse;
import org.olivesafety.member.domain.Member;
import org.olivesafety.member.service.MemberQueryService;
import org.olivesafety.order.converter.OrdersConverter;
import org.olivesafety.order.domain.Orders;
import org.olivesafety.order.dto.OrdersRequestDTO;
import org.olivesafety.order.dto.OrdersResponseDTO;
import org.olivesafety.order.service.OrdersCommandService;
import org.springframework.security.core.Authentication;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Slf4j
@Validated
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/orders")
public class OrdersController {

    private final OrdersCommandService ordersCommandService;
    private final MemberQueryService memberQueryService;

    @PostMapping("/create")
    public ApiResponse<?> orders(@RequestBody OrdersRequestDTO.ordersAddDTO request, Authentication authentication) {
        Member member = memberQueryService.findMemberById(Long.valueOf(authentication.getName().toString())).orElseThrow(() -> new MemberHandler(ErrorStatus.MEMBER_NOT_FOUND));

        ordersCommandService.create(request, member);

        return ApiResponse.of(SuccessStatus._OK,"주문 완료");
    }
}

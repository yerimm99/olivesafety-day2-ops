package org.olivesafety.member.controller;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.olivesafety.common.exception.handler.MemberHandler;
import org.olivesafety.common.exception.status.ErrorStatus;
import org.olivesafety.common.presentation.ApiResponse;
import org.olivesafety.member.domain.Coupon;
import org.olivesafety.member.domain.Member;
import org.olivesafety.member.dto.MemberRequestDTO;
import org.olivesafety.member.dto.MemberResponseDTO;
import org.olivesafety.member.service.MemberCommandService;
import org.olivesafety.member.service.MemberQueryService;
import org.springframework.security.core.Authentication;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletResponse;

@RestController
@Slf4j
@RequiredArgsConstructor
@Validated
@RequestMapping("/api/member")
public class MemberController {

    private final MemberCommandService memberCommandService;
    private final MemberQueryService memberQueryService;

    @PostMapping("/login")
    public ApiResponse<MemberResponseDTO.LoginResultDTO> login(@RequestBody MemberRequestDTO.LoginDTO request, HttpServletResponse response) {

        return ApiResponse.onSuccess(memberCommandService.login(request,response));
    }

    @PostMapping("/coupon")
    public ApiResponse<MemberResponseDTO.CouponResultDTO> issueCoupon(Authentication authentication) {
        Member member = memberQueryService.findMemberById(Long.valueOf(authentication.getName().toString())).orElseThrow(() -> new MemberHandler(ErrorStatus.MEMBER_NOT_FOUND));

        return ApiResponse.onSuccess(memberCommandService.createCoupon(member));
    }
}

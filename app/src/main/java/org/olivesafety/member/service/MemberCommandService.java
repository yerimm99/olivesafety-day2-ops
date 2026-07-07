package org.olivesafety.member.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.olivesafety.common.exception.handler.MemberHandler;
import org.olivesafety.common.exception.status.ErrorStatus;
import org.olivesafety.common.security.provider.TokenProvider;
import org.olivesafety.member.domain.Coupon;
import org.olivesafety.member.domain.repository.CouponRepository;
import org.olivesafety.member.domain.repository.MemberRepository;
import org.olivesafety.member.dto.MemberRequestDTO;
import org.olivesafety.member.dto.MemberResponseDTO;
import org.olivesafety.redis.domain.RefreshToken;
import org.olivesafety.redis.service.RedisService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.olivesafety.member.domain.Member;

import javax.servlet.http.Cookie;
import javax.servlet.http.HttpServletResponse;
import java.time.LocalDateTime;
import java.util.Arrays;
import java.util.UUID;

@Service
@Slf4j
@RequiredArgsConstructor
public class MemberCommandService {

    private final MemberRepository memberRepository;
    private final TokenProvider tokenProvider;
    private final RedisService redisService;
    private final BCryptPasswordEncoder encoder;
    private final CouponRepository couponRepository;

    @Value("${jwt.token.secret}")
    private String key; // 토큰 만들어내는 key값

    public MemberResponseDTO.LoginResultDTO login(MemberRequestDTO.LoginDTO request, HttpServletResponse response) {

        System.out.println(encoder.encode("1234"));

        //email 없음
        Member selectedMember = memberRepository.findByEmail(request.getEmail())
                .orElseThrow(() -> new MemberHandler(ErrorStatus.MEMBER_EMAIL_NOT_FOUND));

        //password 틀림
        if (!encoder.matches(request.getPassword(), selectedMember.getPassword())) {
            throw new MemberHandler(ErrorStatus.MEMBER_PASSWORD_ERROR);
        }

        // refresh 생성후 쿠키로 만들고 response 헤더에 담기
        RefreshToken refreshToken = redisService.generateRefreshToken(request.getEmail());
        Cookie cookie = new Cookie("refreshToken",refreshToken.getToken());
        cookie.setSecure(true);
        cookie.setHttpOnly(true);
        cookie.setPath("/");
        response.addCookie(cookie);

        LocalDateTime currentDateTime = LocalDateTime.now();
        LocalDateTime accessExpireTime = currentDateTime.plusHours(6);



        return MemberResponseDTO.LoginResultDTO.builder()
                .accessToken(redisService.saveLoginStatus(selectedMember.getId(), tokenProvider.createAccessToken(selectedMember.getId(), selectedMember.getEmail().toString() , request.getEmail(), Arrays.asList(new SimpleGrantedAuthority("USER")))))
                .accessExpireTime(accessExpireTime)
                .build();

    }

    public MemberResponseDTO.CouponResultDTO createCoupon(Member member) {

        Coupon coupon = Coupon.builder()
                .code(UUID.randomUUID().toString())
                .used(false)
                .member(member)
                .build();

        couponRepository.save(coupon);

        return MemberResponseDTO.CouponResultDTO.builder()
                .code(coupon.getCode())
                .build();
    }

}

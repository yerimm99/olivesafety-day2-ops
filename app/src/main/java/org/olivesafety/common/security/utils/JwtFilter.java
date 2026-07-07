package org.olivesafety.common.security.utils;


import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.olivesafety.common.exception.handler.JwtHandler;
import org.olivesafety.common.exception.status.ErrorStatus;
import org.olivesafety.common.security.provider.TokenProvider;
import org.olivesafety.redis.service.RedisService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.util.StringUtils;
import org.springframework.web.filter.OncePerRequestFilter;


import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;


//토큰이 있는지 매번 체크해야함
@RequiredArgsConstructor
@Slf4j
public class JwtFilter extends OncePerRequestFilter {

    private final TokenProvider tokenProvider;

    private final RedisService redisService;


    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain) throws ServletException, IOException {


        HttpServletRequest httpServletRequest = request;

        String jwt = tokenProvider.resolveToken(httpServletRequest);
        if (StringUtils.hasText(jwt) && tokenProvider.validateToken(jwt, TokenProvider.TokenType.ACCESS)) {

            // jwt는 정상적인 형태이나, 로그아웃 한 토큰인가?
            if (!redisService.validateLoginToken(jwt)) {
                logger.error("이미 로그아웃 된 토큰 발견");
                throw new JwtHandler(ErrorStatus.JWT_BAD_REQUEST);
            }
            Authentication authentication = tokenProvider.getAuthentication(jwt);
            SecurityContextHolder.getContext().setAuthentication(authentication);
        } else {
            throw new JwtHandler(ErrorStatus.JWT_TOKEN_NOT_FOUND);
        }

        filterChain.doFilter(httpServletRequest, response);
    }
}

package org.olivesafety.common.security.utils;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;

@Component
public class ApiLoggingFilter extends OncePerRequestFilter {

    private static final Logger logger = LoggerFactory.getLogger(ApiLoggingFilter.class);

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {

        // 요청 정보 로깅
        logger.info("Incoming request: method={}, uri={}, params={}",
                request.getMethod(), request.getRequestURI(), request.getParameterMap());

        // 필터 체인 실행
        filterChain.doFilter(request, response);

        // 응답 정보 로깅
        logger.info("Outgoing response: status={}", response.getStatus());
    }
}

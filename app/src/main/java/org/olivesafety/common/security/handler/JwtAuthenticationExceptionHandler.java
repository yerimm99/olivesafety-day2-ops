package org.olivesafety.common.security.handler;

import lombok.RequiredArgsConstructor;
import org.olivesafety.common.exception.handler.JwtHandler;
import org.olivesafety.common.exception.status.ErrorStatus;
import org.olivesafety.common.presentation.ApiResponse;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;


import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.io.PrintWriter;

@Component
@RequiredArgsConstructor
public class JwtAuthenticationExceptionHandler extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain) throws ServletException, IOException {
        try {
            filterChain.doFilter(request, response);
        } catch (JwtHandler authException) {
            response.setContentType("application/json; charset=UTF-8");
            response.setStatus(HttpStatus.UNAUTHORIZED.value());

            PrintWriter writer = response.getWriter();
            ApiResponse apiErrorResult = ApiResponse.onFailure(ErrorStatus.JWT_BAD_REQUEST.getCode(), ErrorStatus.JWT_BAD_REQUEST.getMessage(), "");

            writer.write(apiErrorResult.toString());
            writer.flush();
            writer.close();
        }
    }
}

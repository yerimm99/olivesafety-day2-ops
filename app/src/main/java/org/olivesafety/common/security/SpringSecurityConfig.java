package org.olivesafety.common.security;

import lombok.RequiredArgsConstructor;
import org.olivesafety.common.security.handler.CustomAccessDeniedHandler;
import org.olivesafety.common.security.handler.CustomAuthenticationEntryPoint;
import org.olivesafety.common.security.handler.JwtAuthenticationExceptionHandler;
import org.olivesafety.common.security.utils.ApiLoggingFilter;
import org.olivesafety.common.security.utils.JwtFilter;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.WebSecurityCustomizer;
import org.olivesafety.common.security.provider.TokenProvider;
import org.olivesafety.redis.service.RedisService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

@Configuration
@EnableWebSecurity
@RequiredArgsConstructor
public class SpringSecurityConfig {


    private final CustomAccessDeniedHandler accessDeniedHandler;
    private final CustomAuthenticationEntryPoint authenticationEntryPoint;
    private final JwtAuthenticationExceptionHandler exceptionFilter;
    private final RedisService redisService;
    private final TokenProvider tokenProvider;
    //private final UrlBasedCorsConfigurationSource corsConfigurationSource;
    private final ApiLoggingFilter apiLoggingFilter;

    @Value("${jwt.token.secret}")
    private String secretKey;

    @Bean
    public WebSecurityCustomizer webSecurityCustomizer() {
        return (web) -> web.ignoring()
                .antMatchers(
                        "/favicon.ico",
                        "/health",
                        "/error",
                        "/",
                        "/api/member/login",
                        "/api/item"
                );
    }

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity httpSecurity) throws Exception {

        return httpSecurity
                .httpBasic().disable()//토큰 인증 방식으로 하기 위해서 HTTP 기본 인증 비활성화
                .csrf().disable()//CSRF 공격 방어 기능 비활성화
                .cors()
                //.configurationSource(corsConfigurationSource)


                .and()
                .sessionManagement().sessionCreationPolicy(SessionCreationPolicy.STATELESS)
                .and()
                .authorizeRequests()
                .antMatchers("/**").permitAll()//모든 접근 허용
                //.antMatchers(HttpMethod.POST, "/api/members/jwt/test").authenticated()//인증 필요로 접근 막기

                .and()
                .exceptionHandling()
                .accessDeniedHandler(accessDeniedHandler)
                .and()
                .exceptionHandling()
                .authenticationEntryPoint(authenticationEntryPoint)
                .and()

                .addFilterBefore(apiLoggingFilter, UsernamePasswordAuthenticationFilter.class)
                .addFilterBefore(new JwtFilter(tokenProvider, redisService), UsernamePasswordAuthenticationFilter.class)
                .addFilterBefore(exceptionFilter, JwtFilter.class)
                .build();


    }
}

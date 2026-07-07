package org.olivesafety.common.exception.status;

import lombok.AllArgsConstructor;
import lombok.Getter;
import org.olivesafety.common.exception.BaseErrorCode;
import org.olivesafety.common.exception.ErrorReasonDTO;
import org.springframework.http.HttpStatus;

@Getter
@AllArgsConstructor
public enum ErrorStatus implements BaseErrorCode {

    //Member
    MEMBER_NOT_FOUND(HttpStatus.NOT_FOUND, "MEMBER4004", "해당 회원을 찾을 수 없습니다."),
    MEMBER_PASSWORD_ERROR(HttpStatus.BAD_REQUEST, "MEMBER4002", "비밀번호가 잘못되었습니다."),
    MEMBER_EMAIL_NOT_FOUND(HttpStatus.NOT_FOUND, "MEMBER4003", "이메일이 존재하지 않습니다."),

    //Coupon
    COUPON_NOT_FOUND(HttpStatus.NOT_FOUND, "MEMBER4003", "쿠폰이 존재하지 않습니다."),
    COUPON_NOT_VALID(HttpStatus.NOT_FOUND, "MEMBER4003", "이미 사용한 쿠폰입니다."),

    //JWT
    JWT_BAD_REQUEST(HttpStatus.UNAUTHORIZED, "JWT4001", "잘못된 JWT 서명입니다."),
    JWT_ACCESS_TOKEN_EXPIRED(HttpStatus.UNAUTHORIZED, "JWT4002", "액세스 토큰이 만료되었습니다."),
    JWT_REFRESH_TOKEN_EXPIRED(HttpStatus.UNAUTHORIZED, "JWT4003", "리프레시 토큰이 만료되었습니다. 다시 로그인하시기 바랍니다."),
    JWT_UNSUPPORTED_TOKEN(HttpStatus.UNAUTHORIZED, "JWT4004", "지원하지 않는 JWT 토큰입니다."),
    JWT_TOKEN_NOT_FOUND(HttpStatus.UNAUTHORIZED, "JWT4005", "유효한 JWT 토큰이 없습니다."),

    _INTERNAL_SERVER_ERROR(HttpStatus.INTERNAL_SERVER_ERROR, "COMMON500", "서버 에러, 관리자에게 문의 바랍니다."),
    _BAD_REQUEST(HttpStatus.BAD_REQUEST, "COMMON400", "잘못된 요청입니다."),

    //MQ
    SNS_PUBLISH_FAILED(HttpStatus.INTERNAL_SERVER_ERROR, "SNS4001", "SNS 오류"),

    //Order
    ORDER_NOT_FOUND(HttpStatus.BAD_REQUEST, "ORDER4001", "해당 주문을 찾을 수 없습니다."),
    //ITEM
    ITEM_NOT_FOUND(HttpStatus.NOT_FOUND, "ITEM4001", "해당 상품을 찾을 수 없습니다."),
    LACK_OF_STOCK(HttpStatus.NOT_FOUND, "ITEM4002", "재고가 부족합니다.");
    private final HttpStatus httpStatus;
    private final String code;
    private final String message;

    @Override
    public ErrorReasonDTO getReason() {
        return ErrorReasonDTO.builder()
                .message(message)
                .code(code)
                .isSuccess(false)
                .build();
    }

    @Override
    public ErrorReasonDTO getReasonHttpStatus() {
        return ErrorReasonDTO.builder()
                .message(message)
                .code(code)
                .isSuccess(false)
                .httpStatus(httpStatus)
                .build();
    }
}


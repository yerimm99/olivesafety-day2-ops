package org.olivesafety.common.exception.handler;

import org.olivesafety.common.exception.BaseErrorCode;
import org.olivesafety.common.exception.GeneralException;

public class JwtHandler extends GeneralException {
    public JwtHandler(BaseErrorCode code) {
        super(code);
    }
}

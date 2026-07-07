package org.olivesafety.common.exception.handler;

import org.olivesafety.common.exception.BaseErrorCode;
import org.olivesafety.common.exception.GeneralException;

public class OrdersHandler extends GeneralException {
    public OrdersHandler(BaseErrorCode code) {
        super(code);
    }
}


package org.olivesafety.common.exception.handler;

import org.olivesafety.common.exception.GeneralException;
import org.olivesafety.common.exception.status.ErrorStatus;

public class MemberHandler extends GeneralException {

    public MemberHandler(ErrorStatus errorCode) {
        super(errorCode);
    }
}

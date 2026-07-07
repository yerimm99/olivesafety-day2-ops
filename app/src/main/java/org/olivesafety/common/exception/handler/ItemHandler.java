package org.olivesafety.common.exception.handler;

import org.olivesafety.common.exception.GeneralException;
import org.olivesafety.common.exception.status.ErrorStatus;

public class ItemHandler extends GeneralException {

    public ItemHandler(ErrorStatus errorCode) {
        super(errorCode);
    }
}

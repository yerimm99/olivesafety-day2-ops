package org.olivesafety.common.presentation;


import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthCheck {

    @GetMapping("/")
    public String healthCheck() {
        return "OK, healthy!";
    }
    private static final Logger logger = LoggerFactory.getLogger(HealthCheck.class);

    @GetMapping("/error")
    public String ErrorCheck() throws Exception {
        try {
            // Intentionally throw an exception
            throw new Exception("예외 처리 테스트");
        } catch (Exception e) {
            // Log the error at the ERROR level
            logger.error("An error occurred: ", e);
            throw e; // Re-throw the exception to be handled by Spring's exception handling mechanism
        }
    }

}

package org.olivesafety.redis.domain.repository;

import org.olivesafety.redis.domain.LoginStatus;
import org.springframework.data.repository.CrudRepository;

public interface LoginStatusRepository extends CrudRepository<LoginStatus, String> {
}

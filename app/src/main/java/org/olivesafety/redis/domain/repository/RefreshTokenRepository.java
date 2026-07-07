package org.olivesafety.redis.domain.repository;

import org.olivesafety.redis.domain.RefreshToken;
import org.springframework.data.repository.CrudRepository;


public interface RefreshTokenRepository extends CrudRepository<RefreshToken, String> {


}

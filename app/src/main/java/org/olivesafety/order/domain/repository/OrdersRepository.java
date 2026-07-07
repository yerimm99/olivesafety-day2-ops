package org.olivesafety.order.domain.repository;

import org.olivesafety.order.domain.Orders;
import org.springframework.data.jpa.repository.JpaRepository;

public interface OrdersRepository extends JpaRepository<Orders, Long> {
}

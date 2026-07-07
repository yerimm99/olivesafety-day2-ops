package org.olivesafety.order.domain.repository;


import org.olivesafety.order.domain.OrdersItem;
import org.springframework.data.jpa.repository.JpaRepository;

public interface OrdersItemRepository extends JpaRepository<OrdersItem, Long> {
}

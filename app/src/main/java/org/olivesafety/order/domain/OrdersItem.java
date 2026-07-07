package org.olivesafety.order.domain;

import lombok.*;
import org.olivesafety.common.domain.BaseDateTimeEntity;
import org.olivesafety.item.domain.Item;

import javax.persistence.*;

@Entity
@Getter
@Builder
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
public class OrdersItem extends BaseDateTimeEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "orders_item_id")
    private Long id;

    @Column(nullable = false)
    private Long totalPrice;

    @Column(nullable = false)
    private Long amount;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "orders_id", nullable = false)
    private Orders orders;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "item_id", nullable = false)
    private Item item;

    public void setorders(Orders orders) {
        if (this.orders != null) {
            this.orders.getOrdersItemList().remove(this);
        }
        this.orders = orders;
        orders.getOrdersItemList().add(this);
    }

    public void setItem(Item item) {
        if (this.item != null) {
            this.item.getOrdersItemList().remove(this);
        }
        this.item = item;
        item.getOrdersItemList().add(this);
    }

    public void applyCouponPrice() {
        this.totalPrice -= this.totalPrice / 2;
    }



}

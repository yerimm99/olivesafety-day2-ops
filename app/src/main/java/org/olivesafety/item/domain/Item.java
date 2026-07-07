package org.olivesafety.item.domain;

import lombok.*;
import org.olivesafety.common.domain.BaseDateTimeEntity;
import org.olivesafety.order.domain.OrdersItem;

import javax.persistence.*;
import java.util.ArrayList;
import java.util.List;
@Entity
@Getter
@Builder
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
public class Item extends BaseDateTimeEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "item_id")
    private Long id;

    @Column(nullable = false, length = 300)
    private String name;

    @Column(nullable = false)
    private Long stock;

    private Long price;

    @Column(nullable = false)
    private Long salesCount;

    @Column(columnDefinition = "TEXT", nullable = false)
    private String image;


    @OneToMany(mappedBy = "item", cascade = CascadeType.ALL)
    private List<OrdersItem> ordersItemList = new ArrayList<>();

    // 판매수, 재고 관련 메소드
    public Item updateStock(Long i) {
        this.stock -= i;
        return this;
    }

    public Item updateSales(Long i) {
        this.salesCount += i;
        return this;
    }

}

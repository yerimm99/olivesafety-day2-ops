package org.olivesafety.member.domain;

import lombok.*;
import org.hibernate.annotations.DynamicInsert;
import org.olivesafety.common.domain.BaseDateTimeEntity;
import org.olivesafety.order.domain.Orders;

import javax.persistence.*;
import java.util.ArrayList;
import java.util.List;

@Entity
@Getter
@Builder
@DynamicInsert
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
public class Member extends BaseDateTimeEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "member_id")
    private Long id;

    @Column(columnDefinition = "VARCHAR(20)")
    private String name;

    @Column(columnDefinition = "VARCHAR(40)")
    private String email;

    @Column(columnDefinition = "TEXT")
    private String password;

    // orders 양방향 매핑
    @OneToMany(mappedBy = "member", cascade = CascadeType.ALL)
    private List<Orders> ordersList = new ArrayList<>();

    @OneToMany(mappedBy = "member")
    private List<Coupon> coupons = new ArrayList<>();
}

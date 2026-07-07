package org.olivesafety.member.domain;

import lombok.*;
import org.hibernate.annotations.DynamicInsert;
import org.olivesafety.item.domain.Item;

import javax.persistence.*;
import java.util.ArrayList;
import java.util.List;
import javax.persistence.Entity;

@Entity
@Getter
@Builder
@DynamicInsert
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
public class Coupon {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "coupon_id")
    private Long id;

    private String code;

    private boolean used;

    @ManyToOne
    @JoinColumn(name = "member_id")
    private Member member;

    public Coupon useCoupon() {
        this.used =true;
        return this;
    }

}

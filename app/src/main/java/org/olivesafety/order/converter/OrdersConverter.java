package org.olivesafety.order.converter;

import org.olivesafety.member.domain.Member;
import org.olivesafety.order.domain.Orders;
import org.olivesafety.order.domain.OrdersItem;
import org.olivesafety.order.domain.PayType;
import org.olivesafety.order.dto.OrdersRequestDTO;
import org.olivesafety.order.dto.OrdersResponseDTO;

import java.util.ArrayList;

public class OrdersConverter {

    public static OrdersResponseDTO.ordersAddResultDTO toordersAddResultDto(Orders orders) {
        return OrdersResponseDTO.ordersAddResultDTO.builder()
                .ordersId(orders.getId())
                .createdAt(orders.getCreatedAt())
                .build();
    }

    public static Orders toorders(OrdersRequestDTO.ordersAddDTO request, Member member) {
        PayType payType = null;
        switch (request.getPayType()) {
            case "CARD":
                payType = PayType.CARD;
                break;
            case "CASH":
                payType = PayType.CASH;
                break;
        }
        return Orders.builder()
                .name(request.getName())
                .phone(request.getPhone())
                .payType(payType)
                .member(member)
                .ordersItemList(new ArrayList<>())
                .build();
    }

    public static OrdersItem toordersItem(OrdersRequestDTO.ordersAddDTO request, Long price) {

        return OrdersItem.builder()
                .totalPrice(request.getAmount() * price)
                .amount(request.getAmount())
                .build();
    }

    public static OrdersResponseDTO.OrderMessageDTO toOrderMessage(OrdersRequestDTO.ordersAddDTO request, Long memberId){

        PayType payType = null;
        switch (request.getPayType()) {
            case "CARD":
                payType = PayType.CARD;
                break;
            case "CASH":
                payType = PayType.CASH;
                break;
        }
        return OrdersResponseDTO.OrderMessageDTO.builder()
                .memberId(memberId)
                .itemId(request.getId())
                .name(request.getName())
                .phone(request.getPhone())
                .payType(payType)
                .amount(request.getAmount())
                .build();


    }


}


package org.olivesafety.order.service;

import com.amazonaws.services.sns.AmazonSNS;
import com.amazonaws.services.sns.model.PublishRequest;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.olivesafety.common.exception.handler.ItemHandler;
import org.olivesafety.common.exception.handler.MemberHandler;
import org.olivesafety.common.exception.handler.OrdersHandler;
import org.olivesafety.common.exception.status.ErrorStatus;
import org.olivesafety.item.domain.Item;
import org.olivesafety.item.domain.repository.ItemRepository;
import org.olivesafety.member.domain.Coupon;
import org.olivesafety.member.domain.Member;
import org.olivesafety.member.domain.repository.CouponRepository;
import org.olivesafety.order.converter.OrdersConverter;
import org.olivesafety.order.domain.Orders;
import org.olivesafety.order.domain.OrdersItem;
import org.olivesafety.order.domain.repository.OrdersItemRepository;
import org.olivesafety.order.domain.repository.OrdersRepository;
import org.olivesafety.order.dto.OrdersRequestDTO;
import org.olivesafety.order.dto.OrdersResponseDTO;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.persistence.EntityManager;
import javax.persistence.PersistenceContext;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class OrdersCommandService {

    private final AmazonSNS amazonSNS;

    @Value("${cloud.aws.sns.topic.arn}")
    private String snsTopicArn;

    private final ItemRepository itemRepository;
    private final OrdersRepository ordersRepository;
    private final OrdersItemRepository ordersItemRepository;
    private final CouponRepository couponRepository;


/*
    @Transactional
    public Orders create(OrdersRequestDTO.ordersAddDTO request, Member member) {

        // orders 엔티티 생성 및 연관관계 매핑
        Orders newOrders = OrdersConverter.toorders(request,member);
        ordersRepository.save(newOrders);

        // ordersItem, 연관관계 매핑, 판매 재고 업데이트
        Item item = itemRepository.findByIdWithLock(request.getId()).orElseThrow(()-> new ItemHandler(ErrorStatus.ITEM_NOT_FOUND));
        entityManager.refresh(item);

        // ordersItem 엔티티 생성 및 연관관계 매핑
        OrdersItem newordersItem = OrdersConverter.toordersItem(request, item.getPrice());
        newordersItem.setItem(item);
        newordersItem.setorders(newOrders);

        if (newordersItem.getAmount() > item.getStock()) {
            throw new OrdersHandler(ErrorStatus.LACK_OF_STOCK);
        }

        //쿠폰 사용하는지 검사
        if(request.getCode() != null){

            Coupon coupon = couponRepository.findByCode(request.getCode()).orElseThrow(() -> new MemberHandler(ErrorStatus.COUPON_NOT_FOUND));
            //쿠폰 코드 검사
            if(coupon.isUsed()){
                throw new MemberHandler(ErrorStatus.COUPON_NOT_VALID);
            }

            newordersItem.applyCouponPrice();
            coupon.useCoupon();
        }

        // item의 판매량, 재고 업데이트
        item.updateSales(newordersItem.getAmount());
        item.updateStock(newordersItem.getAmount());

        ordersItemRepository.save(newordersItem);

        // SNS 주제로 주문 생성 메시지 발행
        publishOrderCreatedEvent(newOrders);


        return newOrders;
    }
*/
    @Transactional
    public void create(OrdersRequestDTO.ordersAddDTO request, Member member) {

        OrdersResponseDTO.OrderMessageDTO orderMessage = OrdersConverter.toOrderMessage(request, member.getId());

        // SNS 주제로 주문 생성 메시지 발행
        publishOrderCreatedEvent(orderMessage);


    }


    private void publishOrderCreatedEvent(OrdersResponseDTO.OrderMessageDTO orderMessageDTO) {
        try {
            // 요청 객체와 memberId를 포함한 메시지 생성


            String message = new ObjectMapper().writeValueAsString(orderMessageDTO);

            PublishRequest publishRequest = new PublishRequest()
                    .withTopicArn(snsTopicArn)
                    .withMessage(message)
                    .withMessageGroupId("OrderGroup")  // FIFO 주제에 필요한 MessageGroupId 추가
                    .withMessageDeduplicationId(UUID.randomUUID().toString());

            amazonSNS.publish(publishRequest);
        } catch (Exception e) {
            throw new OrdersHandler(ErrorStatus.SNS_PUBLISH_FAILED);
        }
    }

}

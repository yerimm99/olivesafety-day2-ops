package org.olivesafety.common.presentation;

import com.amazonaws.services.sqs.AmazonSQS;
import com.amazonaws.services.sqs.model.Message;
import com.amazonaws.services.sqs.model.ReceiveMessageRequest;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.olivesafety.common.exception.handler.ItemHandler;
import org.olivesafety.common.exception.handler.MemberHandler;
import org.olivesafety.common.exception.handler.OrdersHandler;
import org.olivesafety.common.exception.status.ErrorStatus;
import org.olivesafety.item.domain.Item;
import org.olivesafety.item.domain.repository.ItemRepository;
import org.olivesafety.member.domain.Member;
import org.olivesafety.member.domain.repository.MemberRepository;
import org.olivesafety.order.converter.OrdersConverter;
import org.olivesafety.order.domain.Orders;
import org.olivesafety.order.domain.OrdersItem;
import org.olivesafety.order.domain.repository.OrdersItemRepository;
import org.olivesafety.order.domain.repository.OrdersRepository;
import org.olivesafety.order.dto.OrdersRequestDTO;
import org.olivesafety.order.dto.OrdersResponseDTO;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.persistence.EntityManager;
import javax.persistence.PersistenceContext;
import java.util.ArrayList;
import java.util.List;

@Slf4j@Service
@RequiredArgsConstructor
public class SqsOrderProcessor {

    private final AmazonSQS amazonSQS;
    private final OrdersRepository ordersRepository;
    private final ItemRepository itemRepository;
    private final OrdersItemRepository ordersItemRepository;
    private final MemberRepository memberRepository;

    @Value("${cloud.aws.sqs.queueUrl}")
    private String queueUrl;

    @Scheduled(fixedRate = 3000)
    @Transactional
    public void pollQueue() {
        try {

            ReceiveMessageRequest receiveMessageRequest = new ReceiveMessageRequest(queueUrl)
                    .withMaxNumberOfMessages(10);

            List<Message> messages = amazonSQS.receiveMessage(receiveMessageRequest).getMessages();
            if (messages.isEmpty()) {
                log.info("No messages received from SQS.");
            }

            for (Message message : messages) {
                processMessage(message);
                amazonSQS.deleteMessage(queueUrl, message.getReceiptHandle());
            }
        } catch (Exception e) {
            log.error("Error during SQS polling", e);
        }
    }


    private void processMessage(Message message) {
        try {
            // 메시지의 "Message" 필드에서 실제 JSON 데이터 추출
            String messageBody = message.getBody();
            ObjectMapper objectMapper = new ObjectMapper();

            // Message 필드를 JSON 형식으로 파싱
            JsonNode rootNode = objectMapper.readTree(messageBody);
            String orderMessageJson = rootNode.get("Message").asText();

            // 추출된 JSON을 OrderMessageDTO로 변환
            OrdersResponseDTO.OrderMessageDTO orderMessageDTO = objectMapper.readValue(orderMessageJson, OrdersResponseDTO.OrderMessageDTO.class);

            // 주문에 해당하는 Member 객체 조회
            Member member = memberRepository.findById(orderMessageDTO.getMemberId())
                    .orElseThrow(() -> new MemberHandler(ErrorStatus.MEMBER_NOT_FOUND));

            // 주문에 포함된 아이템을 처리
            Item item = itemRepository.findById(orderMessageDTO.getItemId())
                    .orElseThrow(() -> new ItemHandler(ErrorStatus.ITEM_NOT_FOUND));



            if (orderMessageDTO.getAmount() > item.getStock()) {
                throw new OrdersHandler(ErrorStatus.LACK_OF_STOCK);
            }
            // Orders 객체 생성 - Builder 패턴 사용
            Orders newOrders = Orders.builder()
                    .member(member)
                    .name(orderMessageDTO.getName())
                    .phone(orderMessageDTO.getPhone())
                    .payType(orderMessageDTO.getPayType())
                    .ordersItemList(new ArrayList<>())
                    .build();

            // OrdersItem 객체 생성 - Builder 패턴 사용
            OrdersItem newOrdersItem = OrdersItem.builder()
                    .item(item)
                    .amount(orderMessageDTO.getAmount())
                    .totalPrice(item.getPrice() * orderMessageDTO.getAmount())
                    .orders(newOrders)
                    .build();

            // 연관 관계 설정
            newOrdersItem.setItem(item);
            newOrdersItem.setorders(newOrders);

            // item의 판매량, 재고 업데이트
            item.updateSales(orderMessageDTO.getAmount());
            item.updateStock(orderMessageDTO.getAmount());




            // Orders 및 OrdersItem 객체를 데이터베이스에 저장
            ordersRepository.save(newOrders);
            ordersItemRepository.save(newOrdersItem);


        } catch (Exception e) {
            log.error("Failed to process order message", e);
        }
    }


}

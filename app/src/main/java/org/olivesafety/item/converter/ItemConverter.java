package org.olivesafety.item.converter;

import org.olivesafety.item.domain.Item;
import org.olivesafety.item.dto.ItemResponseDTO;
import org.olivesafety.order.domain.OrdersItem;
import org.olivesafety.order.dto.OrdersRequestDTO;
import org.springframework.data.domain.Page;

import java.util.List;
import java.util.stream.Collectors;

public class ItemConverter {

    public static ItemResponseDTO.ItemPreviewListDTO itemPreviewListDTO(Page<Item> itemList) {

        List<ItemResponseDTO.ItemPreviewDTO> itemPreviewDTOList = itemList.stream()
                .map(ItemConverter::itemPreviewDTO).collect(Collectors.toList());

        return ItemResponseDTO.ItemPreviewListDTO.builder()
                .itemList(itemPreviewDTOList)
                .isFirst(itemList.isFirst())
                .isLast(itemList.isLast())
                .listSize(itemList.getSize())
                .totalPage(itemList.getTotalPages())
                .totalElements(itemList.getTotalElements())
                .build();
    }

    public static ItemResponseDTO.ItemPreviewDTO itemPreviewDTO(Item item) {

        return ItemResponseDTO.ItemPreviewDTO.builder()
                .itemId(item.getId())
                .name(item.getName())
                .image(item.getImage())
                .price(item.getPrice())
                .build();
    }
}

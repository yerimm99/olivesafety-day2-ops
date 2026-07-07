package org.olivesafety.item.controller;

import lombok.RequiredArgsConstructor;
import org.olivesafety.common.presentation.ApiResponse;
import org.olivesafety.item.converter.ItemConverter;
import org.olivesafety.item.domain.Item;
import org.olivesafety.item.dto.ItemResponseDTO;
import org.olivesafety.item.service.ItemQueryService;
import org.springframework.data.domain.Page;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequiredArgsConstructor
@Validated
@RequestMapping("/api")
public class ItemController {

    private final ItemQueryService itemQueryService;


    @GetMapping("/item")
    public ApiResponse<ItemResponseDTO.ItemPreviewListDTO> getItem(@RequestParam(name = "page") Integer page){
        Page<Item> itemList = itemQueryService.getItem(page);

        return ApiResponse.onSuccess(ItemConverter.itemPreviewListDTO(itemList));
    }

}

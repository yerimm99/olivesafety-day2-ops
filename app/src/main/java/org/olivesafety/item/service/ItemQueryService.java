package org.olivesafety.item.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.olivesafety.item.domain.Item;
import org.olivesafety.item.domain.repository.ItemRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ItemQueryService {

    private final ItemRepository itemRepository;

    public Optional<Item> findItemById(Long id) {
        return itemRepository.findById(id);
    }


    public Page<Item> getItem(Integer page){

        return itemRepository.findAll(PageRequest.of(page - 1, 8));
    }

}

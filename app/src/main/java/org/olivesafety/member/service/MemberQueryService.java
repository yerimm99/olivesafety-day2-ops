package org.olivesafety.member.service;

import lombok.RequiredArgsConstructor;
import org.olivesafety.member.domain.Member;
import org.olivesafety.member.domain.repository.MemberRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class MemberQueryService {

    private final MemberRepository memberRepository;

    public Optional<Member> findMemberById(Long id) {
        return memberRepository.findById(id);
    }
}

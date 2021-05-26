; This implementation is a faithful implementation in x64 assembly.
; It can be used for sieve sizes up to 100,000,000; beyond that some register widths used will become too narrow for
; (first) the sqrt of the size, and then the size itself.

global main

extern printf
extern malloc
extern free

default rel

struc time
    .sec:       resq    1
    .fract:     resq    1
endstruc

struc sieve
    .bitSize: resd    1
    .primes:    resq    1
endstruc

section .data

SIEVE_SIZE      equ     1000000                     ; sieve size
RUNTIME         equ     5                           ; target run time in seconds
TRUE            equ     1                           ; true constant
FALSE           equ     0                           ; false constant
NULL            equ     0                           ; null pointer
SEMICOLON       equ     59                          ; semicolon ascii
INIT_BLOCK      equ     0ffffffffffffffffh          ; init block for prime array            

CLOCK_GETTIME   equ     228                         ; syscall number for clock_gettime
CLOCK_MONOTONIC equ     1                           ; CLOCK_MONOTONIC
WRITE           equ     1                           ; syscall number for write
STDOUT          equ     1                           ; file descriptor of stdout

MILLION         equ     1000000
BILLION         equ     1000000000

refResults:
                dd      10, 4
                dd      100, 25
                dd      1000, 168
                dd      10000, 1229
                dd      100000, 9592
                dd      1000000, 78498
                dd      10000000 ,664579
                dd      100000000, 5761455
                dd      0

; format string for output
outputFmt:      db      'rbergen_x64ff_bit', SEMICOLON, '%d', SEMICOLON, '%d.%03d', SEMICOLON, '1', 10, 0   
; incorrect result warning message
incorrect:      db      'WARNING: result is incorrect!', 10
; length of previous
incorrectLen:   db      $ - incorrect

section .bss

startTime:      resb    time_size                   ; start time of sieve run
duration:       resb    time_size                   ; duration
sizeSqrt:       resd    1                           ; square root of sieve size

section .text

main:

; registers (global variables):
; * r14d: runCount
; * r15: sievePtr (&sieve)

    xor         r14d, r14d

    mov         eax, SIEVE_SIZE                     ; eax = sieve size
    cvtsi2sd    xmm0, eax                           ; xmm0 = eax
    sqrtsd      xmm0, xmm0                          ; xmm0 = sqrt(xmm0)
    cvttsd2si   eax, xmm0                           ; sizeSqrt = xmm0 
    inc         eax                                 ; sizeSqrt++, for safety 
    mov         dword [sizeSqrt], eax               ; save sizeSqrt

; get start time
    mov         rax, CLOCK_GETTIME                  ; syscall to make, parameters:
    mov         rdi, CLOCK_MONOTONIC                ; * ask for monotonic time
    lea         rsi, [startTime]                    ; * struct to store result in
    syscall

    xor         r15, r15                            ; sievePtr = null

runLoop:
    cmp         r15, NULL                           ; if sievePtr == null...
    jz          createSieve                         ; ...skip deletion    
    
    mov         rdi, r15                            ; pass sievePtr
    call        deleteSieve                         ; delete sieve

createSieve:    
    mov         rdi, SIEVE_SIZE                     ; pass sieve size
    call        newSieve                            ; rax = &sieve

    mov         r15, rax                            ; sievePtr = rax

    mov         rdi, r15                            ; pass sievePtr
    call        runSieve                            ; run sieve

; registers: 
; * rax: numNanoseconds/numMilliseconds
; * rbx: numSeconds
; * r14d: runCount
; * r15: sievePtr (&sieve)

    mov         rax, CLOCK_GETTIME                  ; syscall to make, parameters:
    mov         rdi, CLOCK_MONOTONIC                ; * ask for monotonic time
    lea         rsi, [duration]                     ; * struct to store result in
    syscall

    mov         rbx, qword [duration+time.sec]      ; numSeconds = duration.seconds
    sub         rbx, qword [startTime+time.sec]     ; numSeconds -= startTime.seconds

    mov         rax, qword [duration+time.fract]    ; numNanoseconds = duration.fraction    
    sub         rax, qword [startTime+time.fract]   ; numNanoseconds -= startTime.fraction
    jns         checkTime                           ; if numNanoseconds >= 0 then check the duration...
    dec         rbx                                 ; ...else numSeconds--...
    add         rax, BILLION                        ; ...and numNanoseconds += 1,000,000,000

checkTime:
    inc         r14d                                ; runCount++
    cmp         rbx, RUNTIME                        ; if numSeconds < 5...
    jl          runLoop                             ; ...perform another sieve run

; we're past the 5 second mark, so it's time to store the exact duration of our runs
    mov         qword [duration+time.sec], rbx      ; duration.seconds = numSeconds

    xor         edx, edx                            ; edx = 0
    mov         ecx, MILLION                        ; ecx = 1,000,000
    div         ecx                                 ; edx:eax /= ecx, so eax contains numMilliseconds

    mov         qword [duration+time.fract], rax    ; duration.fraction = numMilliseconds

; let's count our primes
    mov         rdi, r15                            ; pass sievePtr
    call        countPrimes                         ; rax = primeCount

; registers:
; * eax: primeCount
; * rcx: refResultPtr
    mov         rcx, refResults                     ; refResultPtr = (int *)&refResults

checkLoop:
    cmp         dword [rcx], 0                      ; if *refResults == 0 then we didn't find our sieve size, so...
    je          printWarning                        ; ...warn about incorrect result
    cmp         dword [rcx], SIEVE_SIZE             ; if *refResults == sieve size...
    je          checkValue                          ; ...check the reference result value...
    add         rcx, 8                              ; ...else refResultsPtr += 2 
    jmp         checkLoop                           ; keep looking for sieve size

checkValue:
    cmp         dword [rcx+4], eax                  ; if *(refResultPtr + 1) == primeCount... 
    je          printResults                        ; ...print result

; if we're here, something's amiss with our outcome
printWarning:

    mov         rax, WRITE                          ; syscall to make, parameters:
    mov         rdi, STDOUT                         ; * write to stdout
    lea         rsi, [incorrect]                    ; * message is warning
    movzx       rdx, byte [incorrectLen]            ; * length of message
    syscall

printResults:
    push        rbp                                 ; align stack (SysV ABI requirement)
                                                    ; parameters for call to printf:
    lea         rdi, [outputFmt]                    ; * format string
    xor         rsi, rsi                            ; * clear...
    mov         esi, r14d                           ; ...and set runCount
    mov         rdx, qword [duration+time.sec]      ; * duration.seconds
    mov         rcx, qword [duration+time.fract]    ; * duration.fraction (milliseconds)
    xor         rax, rax                            ; rax = 0 (no argv)
    call        printf wrt ..plt                             

    pop         rbp                                 ; restore stack

    xor         rax, rax                            ; return 0

    ret                                             ; end of main

; parameters:
; * rdi: sieve limit
; returns:
; * rax: &sieve
newSieve:

    mov         r12, rdi                            ; keep parameter, we'll need it later

    mov         rdi, sieve_size                     ; ask for sieve_size bytes
    call        malloc wrt ..plt                    ; rax = &sieve

    inc         r12d                                ; array_size = sieve limit + 1
    shr         r12d, 1                             ; array_size /= 2
    mov         dword [rax+sieve.bitSize], r12d     ; sieve.bitSize = array_size

; registers:
; * rax = primesPtr (&sieve.primes[0])
; * ecx = initBlockIndex
; * rdx = init_block
; * r12 = sievePtr (&sieve)
; * r13d = initBlockCount

    mov         r12, rax                            ; sievePtr = &sieve
    mov         r13d, dword [r12+sieve.bitSize]     ; initBlockCount = sieve.bitSize
    shr         r13d, 6                             ; initBlockCount /= 64
    inc         r13d                                ; initBlockCount++
    
    lea         rdi, [8*r13d]                       ; ask for initBlockCount * 8 bytes
    call        malloc wrt ..plt                    ; rax = &array[0]

    mov         qword [r12+sieve.primes], rax       ; sieve.primes = rax

; initialize prime array   
    xor         rcx, rcx                            ; initBlockIndex = 0                       
    mov         rdx, INIT_BLOCK                     ; rax = &init_block

initLoop:
    mov         qword [rax+8*rcx], rdx              ; sieve.primes[initBlockIndex*8][0..63] = true
    inc         ecx                                 ; initBlockIndex++
    cmp         ecx, r13d                           ; if initBlockIndex < initBlockCount...
    jb          initLoop                            ; ...continue initialization

    mov         rax, r12                            ; return &sieve

    ret                                             ; end of newSieve

; parameters:
; * rdi: sievePtr (&sieve)
deleteSieve:
    mov         r12, rdi                            ; keep sievePtr, we'll need it later

    mov         rdi, [r12+sieve.primes]             ; ask to free sieve.primes
    call        free wrt ..plt

    mov         rdi, r12                            ; ask to free sieve
    call        free wrt ..plt

    ret                                             ; end of deleteSieve

; parameters:
; * rdi: sievePtr (&sieve)
; returns:
; * &sieve.primes[0]
runSieve:

; registers:
; * eax: index
; * rbx: primesPtr (&sieve.primes[0])
; * rcx: bitNumber/curWord
; * rdx: bitSelect
; * r8d: factor
; * r13d: sizeSqrt (global)

    mov         rbx, [rdi+sieve.primes]             ; primesPtr = &sieve.primes[0]
    mov         r8, 3                               ; factor = 3

sieveLoop:
    mov         rax, r8                             ; index = factor...
    mul         r8d                                 ; ... * factor
    shr         eax, 1                              ; index /= 2

; clear multiples of factor
unsetLoop:
; This code uses btr to unset bits directly in memory. It's an expensive instruction to use, but my guess is that the 
; CPU microcode to perform byte address and bit number calculation, memory read, AND NOT and memory write is faster 
; than an implementation of the same that I could write myself. When finding the next factor that is different,
; because then we're effectively checking sequential bits.  
    btr         dword [rbx], eax                    ; sieve.primes[0][index] = false
    add         eax, r8d                            ; index += factor
    cmp         eax, [rdi+sieve.bitSize]            ; if index < sieve.bitSize...
    jb          unsetLoop                           ; ...continue marking non-primes

; find next factor
    add         r8d, 2                              ; factor += 2
    cmp         r8d, r13d                           ; if factor > sizeSqrt...
    ja          endRun                              ; ...end this run

; this is where we calculate word index and bit number, once 
    mov         eax, r8d                            ; index = factor
    shr         eax, 1                              ; index /= 2
    mov         rcx, rax                            ; bitNumber = index
    and         rcx, 63                             ; bitNumber &= 0b00111111
    mov         rdx, 1                              ; bitSelect = 1
    shl         rdx, cl                             ; bitSelect <<= bitNumber
    shr         eax, 6                              ; index /= 64

factorWordLoop:
    mov         rcx, qword [rbx+8*rax]              ; curWord = sieve.primes[(8 * index)..(8 * index + 7)]

; now we cycle through the bits until we find one that is set
factorBitLoop:
    test        rcx, rdx                            ; if curWord & bitSelect != 0...
    jnz         sieveLoop                           ; ...continue this run

    add         r8d, 2                              ; factor += 2
    cmp         r8d, r13d                           ; if factor > sizeSqrt...
    ja          endRun                              ; ...end this run

    shl         rdx, 1                              ; bitSelect <<= 1
    jnz         factorBitLoop                       ; if bitSelect != 0 then continue looking

; we just shifted the select bit out of rdx, so we need to move on the next memory word
    inc         eax                                 ; index++
    mov         rdx, 1                              ; bitSelect = 1
    jmp         factorWordLoop                      ; continue looking

endRun:
    lea         rax, [rbx]                          ; return &sieve.primes[0]

    ret                                             ; end of runSieve

; parameters:
; * rdi: sievePtr (&sieve)
; returns:
; * primeCount
countPrimes:

; registers:
; * eax: primeCount
; * rbx: primesPtr (&sieve.primes[0])
; * ecx: bitIndex

; This procedure could definitely be made faster by loading (q)words and shifting bits. As the counting of the 
; primes is not included in the timed part of the implementation and executed just once, I just didn't bother.

    mov         rbx, [rdi+sieve.primes]             ; primesPtr = &sieve.primes[0]
    mov         eax, 1                              ; primeCount = 1
    mov         rcx, 1                              ; bitIndex = 1
    
countLoop:
    bt          dword [rbx], ecx                    ; if !sieve.primes[0][bitIndex]...
    jnc         nextItem                            ; ...move on to next array member
    inc         eax                                 ; ...else primeCount++

nextItem:
    inc         ecx                                 ; bitIndex++
    cmp         ecx, dword [rdi+sieve.bitSize]      ; if bitIndex < sieve.bitSize...
    jb          countLoop                           ; ...continue counting

    ret                                             ; end of countPrimes
; This implementation is the most straightforward sieve runner I could code in assembly, and as such unfaithful.
; It can be used for sieve sizes up to 100,000,000; beyond that some register widths used will become too narrow for
; (first) the sqrt of the size, and then the size itself.

global main

extern printf

default rel

struc time
    .sec:       resq    1
    .fract:     resq    1
endstruc

section .data

SIEVE_SIZE      equ     1000000                     ; sieve size
RUNTIME         equ     5                           ; target run time in seconds
BIT_SIZE        equ     (SIEVE_SIZE+1)/2            ; prime candidate bit count
BLOCK_COUNT     equ     (BIT_SIZE/64)+1             ; 8-byte block size
BYTE_SIZE       equ     BLOCK_COUNT*8               ; bytes needed
TRUE            equ     1                           ; true constant
FALSE           equ     0                           ; false constant
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
                dd      10000000, 664579
                dd      100000000, 5761455
                dd      0

; format string for output
outputFmt:      db      'rbergen_x64uff_bit', SEMICOLON, '%d', SEMICOLON, '%d.%03d', SEMICOLON, '1', 10, 0   
; incorrect result warning message
incorrect:      db      'WARNING: result is incorrect!', 10
; length of previous
incorrectLen:   db      $ - incorrect

section .bss

startTime:      resb    time_size                   ; start time of sieve run
duration:       resb    time_size                   ; duration
bPrimes:        resb    BYTE_SIZE                   ; array with prime candidates

section .text

main:

; registers:
; * r12d: run count, throughout program

    xor         r12d, r12d

; registers: all except r12d operational

; calculate square root of sieve size
    mov         eax, SIEVE_SIZE                     ; eax = sieve size
    cvtsi2sd    xmm0, eax                           ; xmm0 = eax
    sqrtsd      xmm0, xmm0                          ; xmm0 = sqrt(xmm0)
    cvttsd2si   r8d, xmm0                           ; sizeSqrt = xmm0 
    inc         r8d                                 ; sizeSqrt++, for safety 

; get start time
    mov         rax, CLOCK_GETTIME                  ; syscall to make, parameters:
    mov         rdi, CLOCK_MONOTONIC                ; * ask for monotonic time
    lea         rsi, [startTime]                    ; * struct to store result in
    syscall

runLoop:

; initialize prime array   
    mov         ecx, 0                              ; arrayIndex = 0                       
    mov         rax, INIT_BLOCK

initLoop:
    mov         qword [bPrimes+8*ecx], rax          ; bPrimes[arrayIndex*8][0..63] = true
    inc         ecx                                 ; arrayIndex++
    cmp         ecx, BLOCK_COUNT                    ; if arrayIndex < array size...
    jb          initLoop                            ; ...continue initialization

; run the sieve

; registers:
; * eax: index
; * ebx: factor
; * rcx: bitNumber/curWord
; * r8d: sizeSqrt
; * r12d: runCount

    mov         rbx, 3                              ; factor = 3

sieveLoop:
    mov         rax, rbx                            ; index = factor...
    mul         ebx                                 ; ... * factor
    shr         eax, 1                              ; index /= 2

; clear multiples of factor
unsetLoop:
; This code uses btr to unset bits directly in memory. It's an expensive instruction to use, but my guess is that the 
; CPU microcode to perform byte address and bit number calculation, memory read, AND NOT and memory write is faster 
; than an implementation of the same that I could write myself. When finding the next factor that is different,
; because then we're effectively checking sequential bits.  
    btr         dword [bPrimes], eax                ; bPrimes[0][index] = false
    add         eax, ebx                            ; index += factor
    cmp         eax, BIT_SIZE                       ; if index < bit count...
    jb          unsetLoop                           ; ...continue marking non-primes

; find next factor
    add         ebx, 2                              ; factor += 2
    cmp         ebx, r8d                            ; if factor > sizeSqrt...
    ja          endRun                              ; ...end this run

; this is where we calculate word index and bit number, once 
    mov         eax, ebx                            ; index = factor
    shr         eax, 1                              ; index /= 2
    mov         rcx, rax                            ; bitNumber = index
    and         rcx, 63                             ; bitNumber &= 0b00111111
    mov         rdx, 1                              ; bitSelect = 1
    shl         rdx, cl                             ; bitSelect <<= bitNumber
    shr         eax, 6                              ; index /= 64

factorWordLoop:    
    mov         rcx, qword [bPrimes+8*eax]          ; curWord = bPrimes[(8 * index)..(8 * index + 7)]

; now we cycle through the bits until we find one that is set
factorBitLoop:
    test        rcx, rdx                            ; if curWord & bitSelect != 0...
    jnz         sieveLoop                           ; ...continue this run

    add         ebx, 2                              ; factor += 2
    cmp         ebx, r8d                            ; if factor > sizeSqrt...
    ja          endRun                              ; ...end this run

    shl         rdx, 1                              ; bitSelect <<= 1
    jnz         factorBitLoop                       ; if bitSelect != 0 then continue looking

; we just shifted the select bit out of the register, so we need to move on the next word
    inc         eax                                 ; index++
    mov         rdx, 1                              ; bitSelect = 1
    jmp         factorWordLoop                      ; continue looking

endRun:

; registers: 
; * rax: numNanoseconds/numMilliseconds
; * rbx: numSeconds
; * r12d: runCount

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
    inc         r12d                                ; runCount++
    cmp         rbx, RUNTIME                        ; if numSeconds < 5...
    jl          runLoop                             ; ...perform another sieve run

; we're past the 5 second mark, so it's time to store the exact duration of our runs
    mov         qword [duration+time.sec], rbx      ; duration.seconds = numSeconds

    mov         ecx, MILLION                        ; ecx = 1,000,000
    div         ecx                                 ; eax /= ecx, so eax contains numMilliseconds

    mov         qword [duration+time.fract], rax    ; duration.fraction = numMilliseconds

; let's count our primes

; registers:
; * ebx: primeCount
; * ecx: bitIndex
; * r12d: runCount

; This code could definitely be made faster by loading (q)words and shifting bits. As the counting of the 
; primes is not included in the timed part of the implementation and executed just once, I just didn't bother.

    mov         ebx, 1                              ; primeCount = 1 
    mov         ecx, 1                              ; bitIndex = 1
    
countLoop:    
    bt          dword [bPrimes], ecx                ; if !bPrimes[0][bitIndex]...
    jnc         nextItem                            ; ...move on to next array member
    inc         ebx                                 ; ...else primeCount++

nextItem:
    inc         ecx                                 ; bitIndex++
    cmp         ecx, BIT_SIZE                       ; if bitIndex <= bit count...
    jb          countLoop                           ; ...continue counting

; we're done counting, let's check our result

; registers:
; * ebx: primeCount
; * rcx: refResultPtr
; * r12d: runCount
    mov         rcx, refResults                     ; refResultPtr = (int *)&refResults

checkLoop:
    cmp         dword [rcx], 0                      ; if *refResults == 0 then we didn't find our sieve size, so...
    je          printWarning                        ; ...warn about incorrect result
    cmp         dword [rcx], SIEVE_SIZE             ; if *refResults == sieve size...
    je          checkValue                          ; ...check the reference result value...
    add         rcx, 8                              ; ...else refResultsPtr += 2 
    jmp         checkLoop                           ; keep looking for sieve size

checkValue:
    cmp         dword [rcx+4], ebx                  ; if *(refResultPtr + 1) == primeCount... 
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
    xor         rsi, rsi                            ; * clear and pass..
    mov         esi, r12d                           ; ...runCount
    mov         rdx, qword [duration+time.sec]      ; * duration.seconds
    mov         rcx, qword [duration+time.fract]    ; * duration.fraction (milliseconds)
    xor         eax, eax                            ; eax = 0 (no argv)
    call        printf wrt ..plt                             

    pop         rbp                                 ; restore stack

    xor         rax, rax

    ret                                             ; done!
// This implementation is a faithful implementation in arm64 assembly.
// It can be used for sieve sizes up to 100,000,000; beyond that some register widths used will become too narrow.

.arch armv8-a+simd

.global main

.extern printf
.extern malloc
.extern free

            .struct     0
time_sec:   
            .struct     time_sec + 8
time_fract: 
            .struct     time_fract + 8
time_size:

            .struct     0
sieve_arraySize:    
            .struct     sieve_arraySize + 4
sieve_primes:       
            .struct     sieve_primes + 8
sieve_size:

.equ        SIEVE_LIMIT,    1000000     // sieve size
.equ        RUNTIME,        5           // target run time in seconds
.equ        FALSE,          0           // false constant
.equ        NULL,           0           // null pointer
.equ        INIT_PATTERN,   0xffff      // init pattern for prime array
.equ        WORD_MASK,      0x31        // mask to retain last 5 bits of bit index

.equ        CLOCK_GETTIME,  113         // syscall number for clock_gettime
.equ        CLOCK_MONOTONIC,1           // CLOCK_MONOTONIC
.equ        WRITE,          64          // syscall number for write
.equ        STDOUT,         1           // file descriptor of stdout

.equ        MILLION,        1000000
.equ        BILLION,        1000000000


.data

.balign     8

refResults:
.word       10, 4
.word       100, 25
.word       1000, 168
.word       10000, 1229
.word       100000, 9592
.word       1000000, 78498
.word       10000000, 664579
.word       100000000, 5761455
.word       0

.balign     4

startTime:                              // start time of sieve run
.skip       time_size                           

.balign     4

duration:                               // duration
.skip       time_size                           

.text

main:
    stp     x29, x30, [sp, #-16]!       // push x29 and x30 on stack; libc calls will change them

// registers (global variables):
// * x22: billion
// * x24: sieveSize
// * w25: runCount
// * x26: sievePtr (&sieve)
// * w27: sizeSqrt
// * x28: initBlock

    movz    x28, INIT_PATTERN           // set 2 rightmost WORDs of initBlock...
    movk    x28, INIT_PATTERN, lsl 16   // ...then the 2 left of that... 
    movk    x28, INIT_PATTERN, lsl 32   // ...then the 2 left of that...
    movk    x28, INIT_PATTERN, lsl 48   // ...then the 2 leftmost

    ldr     x22, =BILLION               // billion = BILLION      

    mov     w25, #0                     // runCount = 0

    ldr     x24, =SIEVE_LIMIT           // sieveSize = sieve size

    ucvtf   s0, x24                     // s0 = sieveSize
    fsqrt   s0, s0                      // s0 = sqrt(s0)
    fcvtau  x27, s0                     // sizeSqrt = s0 
    add     w27, w27, #1                // sizeSqrt++, for safety 

// get start time
    mov     x8, CLOCK_GETTIME           // syscall to make, parameters:
    mov     x0, CLOCK_MONOTONIC         // * ask for monotonic time
    adr     x1, startTime               // * struct to store result in
    svc     #0

    mov     x26, #0                     // sievePtr = null

runLoop:
    cbz     x26, createSieve            // if sievePtr == null then skip deletion
    
    mov     x0, x26                     // pass sievePtr
    bl      deleteSieve                 // delete sieve

createSieve:    
    mov     x0, x24                     // pass sieve size
    bl      newSieve                    // x0 = &sieve

    mov     x26, x0                     // sievePtr = x0

    bl      runSieve                    // run sieve

// registers: 
// * x0: numDurationSeconds
// * x1: numDurationNanoseconds/numDurationMilliseconds
// * x2: startTimePtr
// * x3: numStartTimeSeconds/numStartTimeNanoseconds
// * x22: billion
// * x23: durationPtr
// * x24: sieveSize
// * w25: runCount
// * x26: sievePtr (&sieve)

    mov     x8, CLOCK_GETTIME           // syscall to make, parameters:
    mov     x0, CLOCK_MONOTONIC         // * ask for monotonic time
    adr     x1, duration                // * struct to store result in
    svc     #0

    adr     x2, startTime               // startTimePtr = &startTime
    adr     x23, duration               // durationPtr = &duration

    ldr     x0, [x23, #time_sec]        // numDurationSeconds = duration.seconds
    ldr     x3, [x2, #time_sec]         // numStartTimeseconds = starttime_seconds
    sub     x0, x0, x3                  // numDurationSeconds -= numStartTimeseconds

    ldr     x1, [x23, #time_fract]      // numDurationNanoseconds = duration.fraction
    ldr     x3, [x2, #time_fract]       // numStartTimeNanoseconds = starttime_fract
    subs    x1, x1, x3                  // numDurationNanoseconds -= numStartTimeNanoseconds

    bpl     checkTime                   // if numNanoseconds >= 0 then check the duration...
    sub     x0, x0, #1                  // ...else numSeconds--...
    add     x1, x1, x22                 // ...and numNanoseconds += billion

checkTime:
    add     w25, w25, #1                // runCount++
    cmp     x0, RUNTIME                 // if numSeconds < 5...
    blo     runLoop                     // ...perform another sieve run

// we're past the 5 second mark, so it's time to store the exact duration of our runs
    str     x0, [x23, #time_sec]        // duration.seconds = numSeconds

    ldr     x2, =MILLION                // x2 = 1,000,000
    udiv    x1, x1, x2                  // x1 /= x2, so x1 contains numMilliseconds

    str     x1, [x23, #time_fract]      // duration.fraction = numMilliseconds

// let's count our primes
    mov     x0, x26                     // pass sievePtr
    bl      countPrimes                 // x0 = primeCount

// registers:
// * x0: primeCount
// * x1: refResultPtr
// * w2: curSieveSize/curResult
// * x23: durationPtr
// * x24: sieveSize
// * w25: runCount

    adr     x1, refResults              // refResultPtr = (int *)&refResults

checkLoop:
    ldr     w2, [x1]                    // curSieveSize = *refResultPtr
    cbz     w2, printWarning            // if curSieveSize == 0 then we didn't find our sieve size, so warn about incorrect result
    cmp     w2, w24                     // if curSieveSize == sieveSize...
    beq     checkValue                  // ...check the reference result value...
    add     x1, x1, #8                  // ...else refResultsPtr += 2 
    b       checkLoop                   // keep looking for sieve size

checkValue:
    ldr     w2, [x1, #4]                // curResult = *(refResultPtr + 1)
    cmp     w2, w0                      // if curResult == primeCount... 
    beq     printResults                // ...print result

// if we're here, something's amiss with our outcome
printWarning:
    mov     x8, WRITE                   // syscall to make, parameters:
    mov     x0, STDOUT                  // * write to stdout
    adr     x1, incorrect               // * message is warning
    mov     x2, incorrectLen            // * length of message
    svc     #0

printResults:
                                        // parameters for call to printf:
    adr     x0, outputFmt               // * format string
    mov     w1, w25                     // * runCount
    ldr     x2, [x23, #time_sec]        // * duration.seconds
    ldr     x3, [x23, #time_fract]      // * duration.fraction (milliseconds)
    bl      printf                             

    mov     x0, #0                      // return 0

    ldp     x29, x30, [sp], #16         // pop x29 and x30 from stack
    ret                                 // end of main

.balign     4

outputFmt:                              // format string for output
.asciz      "rbergen_arm64;%d;%d.%03d;1\n"   

.balign     4

incorrect:                              // incorrect result warning message
.asciz      "WARNING: result is incorrect!\n"

.equ        incorrectLen, . - incorrect // length of previous

.balign     4 

// parameters:
// * x0: sieve limit
// returns:
// * x0: &sieve
newSieve:
    stp     x29, x30, [sp, #-16]!       // push x29 and x30 on stack; libc calls will change them

// registers:
// * x20 = sievePtr (&sieve)

    mov     x19, x0                     // keep parameter, we'll need it later

    mov     x0, #sieve_size             // ask for sieve_size WORDs
    bl      malloc                      // x0 = &sieve

    mov     x20, x0                     // sievePtr = x0

    add     w19, w19, #1                // array_size = sieve limit + 1
    lsr     w19, w19, #1                // array_size /= 2
    str     w19, [x0, #sieve_arraySize] // sieve.arraySize = array_size

// registers:
// * x0 = initBlockBytes
// * x1 = initBlockIndex
// * x2 = init_block
// * w19 = initBlockCount
// * x20 = sievePtr (&sieve)
// * x28 = initBlock

    lsr     w19, w19, #6                // initBlockCount /= 64
    add     w19, w19, #1                // initBlockCount++
    
    mov     x0, #0                      // initBlockBytes = 0
    mov     w0, w19                     // initBlockBytes = initBlockCount
    lsl     w0, w0, #3                  // initBlockBytes *= 8
    bl      malloc                      // x0 = &array[0]

    str     x0, [x20, #sieve_primes]    // sieve.primes = x0

// initialize prime array   
    mov     x1, #0                      // initBlockIndex = 0                       

initLoop:
    str     x28, [x0, x1, lsl #3]       // sieve.primes[initBlockIndex*8][0..63] = true
    add     x1, x1, #1                  // initBlockIndex++
    cmp     w1, w19                     // if initBlockIndex < initBlockCount...
    blo     initLoop                    // ...continue initialization

    mov     x0, x20                     // return sievePtr

    ldp     x29, x30, [sp], #16         // pop x29 and x30 from stack
    ret                                 // end of newSieve

// parameters:
// * x0: sievePtr (&sieve)
deleteSieve:
    stp     x29, x30, [sp, #-16]!       // push x29 and x30 on stack; libc calls will change them

    mov     x19, x0                     // keep sievePtr, we'll need it later

    ldr     x0, [x19, #sieve_primes]    // ask to free sieve.primes
    bl      free

    mov     x0, x19                     // ask to free sieve
    bl      free

    ldp     x29, x30, [sp], #16         // pop x29 and x30 from stack
    ret                                 // end of deleteSieve

// parameters:
// * x0: sievePtr (&sieve)
// returns:
// * &sieve_primes[0]
runSieve:

// registers:
// * x0: bitSelectPtr
// * x1: primesPtr (&sieve.primes[0])
// * x2: factor
// * x3: bitIndex
// * x4: wordIndex/wordPtr
// * x5: bitNumber
// * w6: curPrimeWord
// * w7: curBitSelect
// * w8: arraySize
// * w27: sizeSqrt (global)

    ldr     x1, [x0, #sieve_primes]     // primesPtr = (int *)&sieve.primes[0]
    ldr     w8, [x0, #sieve_arraySize]  // arraySize = sieve.arraySize
    adr     x0, bitSelect               // bitSelectPtr = (int *)&bitSelect   
    mov     x2, #3                      // factor = 3

sieveLoop:
    mul     x3, x2, x2                  // bitIndex = factor * factor
    lsr     x3, x3, #1                  // bitIndex /= 2

// clear multiples of factor
unsetLoop:
    lsr     x4, x3, #5                  // wordIndex = bitIndex / 32
    ldr     w6, [x1, x4, lsl #2]        // curPrimeWord = sieve.primes[wordIndex * 4]
    and     x5, x3, WORD_MASK           // bitNumber = bitIndex & WORD_MASK
    ldr     w7, [x0, x5, lsl #2]        // curBitSelect = bitSelectPtr[bitNumber * 4]
    bic     w6, w6, w7                  // curPrimeWord &= ~curBitSelect
    str     w6, [x1, x4, lsl #2]    	// sieve.primes[wordIndex * 4] = curPrimeWord
    add     x3, x3, x2                  // bitIndex += factor
    cmp     x3, w8, uxtx                // if bitIndex < arraySize...
    blo     unsetLoop                   // ...continue marking non-primes

    add     x2, x2, #2                  // factor += 2
    cmp     x2, w27, uxtx               // if factor > sizeSqrt...
    bhi     endRun                      // ...end this run

    lsr     x3, x2, #1                  // bitIndex = factor / 2
    lsr     x4, x3, #5                  // wordIndex = bitIndex / 32
    lsl     x4, x4, #2                  // wordIndex *= 4
    add     x4, x1, x4                  // wordPtr = primesPtr + wordIndex
    ldr     w6, [x4], #4                // curPrimeWord = *wordPtr; wordPtr += 4
    and     x5, x3, WORD_MASK           // bitNumber = bitIndex & WORD_MASK
    ldr     w7, [x0, x5, lsl #2]        // curBitSelect = bitSelectPtr[bitNumber * 4]

// find next factor
factorLoop:
    and     w6, w6, w7                  // curPrimeWword &= curBitSelect
    cbnz    w6, sieveLoop               // if curPrimeWord != 0 then continue run

    add     x2, x2, #2                  // factor += 2
    cmp     x2, w27, uxtx               // if factor > sizeSqrt...
    bhi     endRun                      // ...end this run

    lsl     w7, w7, #1                  // curBitSelect <<= 1
    cbnz    w7, factorLoop              // if curBitSelect != 0 then continue looking

// we just shifted the selector bit out of curBitSelect, so we have to move on the next word
    ldr     w6, [x4], #4                // curPrimeWord = *wordPtr; wordPtr += 4
    mov     w7, #1                      // bitSelector = 1

    b       factorLoop                  // continue looking

endRun:
    mov     x0, x1                      // return &sieve.primes[0]

    ret                                 // end of runSieve

.balign     4

bitSelect:
.word       0x00000001, 0x00000002, 0x00000004, 0x00000008
.word       0x00000010, 0x00000020, 0x00000040, 0x00000080
.word       0x00000100, 0x00000200, 0x00000400, 0x00000800
.word       0x00001000, 0x00002000, 0x00004000, 0x00008000
.word       0x00010000, 0x00020000, 0x00040000, 0x00080000
.word       0x00100000, 0x00200000, 0x00400000, 0x00800000
.word       0x01000000, 0x02000000, 0x04000000, 0x08000000
.word       0x10000000, 0x20000000, 0x40000000, 0x80000000

// parameters:
// * x0: sievePtr (&sieve)
// returns:
// * primeCount
countPrimes:

// registers:
// * w0: primeCount
// * w1: bitCount
// * x2: primesPtr (&sieve.primes[0])
// * w3: shiftCount
// * x4: curPrimeWord

    ldr     w1, [x0, #sieve_arraySize]  // bitCount = sieve.arraySize
    ldr     x2, [x0, #sieve_primes]     // primesPtr = &sieve.primes[0]
    ldr     x5, [x2], #8                // curPrimeWord = *primesPtr, primesPtr += 8
    mov     w0, #1                      // primeCount = 1
    sub     w1, w1, #1                  // bitCount--
    lsr     x4, #1                      // curPrimeWord >>= 1
    mov     w3, #63                     // shiftCount = 63

countLoop:    
    lsr     x4, #1                      // curPrimeWord >>= 1
    cinc    w0, w0, cs                  // if the bit we shifted out was set then primeCount++
    sub     w1, w1, #1                  // bitCount--
    cbz     w1, endCount                // if bitCount == 0 then we're done counting

    sub     w3, w3, #1                  // shiftCount--
    cbnz    w3, countLoop               // if shiftCount != 0 then continue counting

// time to move on to the next word
    ldr     x4, [x2], #8                // curPrimeWord = *primesPtr, primesPtr += 8
    mov     w3, #64                     // shiftCount = 64
    b       countLoop                   // continue counting

endCount:
    ret                                 // end of countPrimes


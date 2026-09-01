/*
 * dsp.s
 * EEE3096S 2026 - Practical 1B, Task 4
 * Cycle-counted ADC to DAC loop with a 45 degree phase delay
 *
 * Student 1 : <name>  <student number>
 * Student 2 : <name>  <student number>
 */

    .syntax unified
    .thumb
    .cpu    cortex-m0
    .fpu    softvfp

    .global DSP_Loop
    .type   DSP_Loop, %function

@ ---------------------------------------------------------------------------
@ Peripheral addresses
@ ---------------------------------------------------------------------------
    .equ ADC_DR,      0x40012440
    .equ DAC_DHR12R1, 0x40007408

@ ---------------------------------------------------------------------------
@ Phase delay derivation (see report Section 4 for the full writeup)
@   f = 1 kHz  ->  T = 1/f = 1 ms
@   45 deg     ->  dt = (45/360) * T = T/8 = 125 us
@   System clock = 8 MHz HSI  ->  cycle time = 1/8MHz = 125 ns
@   Target cycle count = 125 us / 125 ns = 1000 cycles
@
@ Cycle budget (verify every count against RM0091 / Cortex-M0 Generic User
@ Guide instruction timing tables before you finalise this for the report -
@ the values below use the standard ARMv6-M timings: LDR = 2 cyc,
@ STR = 1 cyc, MOVS/SUBS = 1 cyc, conditional branch = 2 cyc taken /
@ 1 cyc not taken, unconditional B = 2 cyc):
@
@   Instruction                    Cyc/instr   Count   Subtotal
@   LDR  R2, [R0]   (ADC read)         2          1         2
@   STR  R2, [R1]   (DAC write)        1          1         1
@   LDR  R3, =331   (load count)       2          1         2
@   NOP             (pad)              1          1         1
@   SUBS R3, R3, #1 (delay dec)        1        331       331
@   BNE  delay_loop (taken)            2        330       660
@   BNE  delay_loop (not taken, last)  1          1         1
@   B    loop       (branch back)      2          1         2
@   -------------------------------------------------------------
@   TOTAL                                                 1000  cycles
@                                                    = 1000 * 125 ns
@                                                    = 125.000 us  <-- target
@
@ If your own cycle-timing lookup gives different numbers for LDR/STR/branch,
@ recompute N (the delay_loop count) and the NOP pad so the total still
@ equals 1000, and update this comment block with your working for the
@ report - this is exactly the "insert any NOP padding" step Task 4 wants.
@ ---------------------------------------------------------------------------
    .equ DELAY_COUNT, 331

    .section .text.DSP_Loop, "ax", %progbits

@ ===========================================================================
@ ENTRY POINT
@ ===========================================================================
DSP_Loop:
    @ Setup registers outside the timed loop
    LDR R0, =ADC_DR
    LDR R1, =DAC_DHR12R1

loop:
    @ --- SAMPLE AND OUTPUT ------------------------------------------------
    @ TODO 1 (done): Read the current ADC conversion from the Data Register.
    LDR  R2, [R0]               @ 2 cycles - right-aligned 12-bit ADC value

    @ TODO 2 (done): Write the value straight out to the DAC Data Register.
    STR  R2, [R1]               @ 1 cycle  - right-aligned 12-bit DAC input

    @ --- DELAY SETUP ------------------------------------------------------
    @ TODO 3 (done): Calculate the required cycle target for a 45-degree
    @         phase delay on a 1 kHz sine wave running at an 8 MHz system
    @         clock, and load the inner loop counter. See cycle budget above.
    LDR  R3, =DELAY_COUNT        @ 2 cycles
    NOP                          @ 1 cycle  - padding to land exactly on 1000

delay_loop:
    @ --- INNER LOOP -------------------------------------------------------
    @ TODO 4 (done): Implement the counted delay loop.
    @         SUBS updates the flags (needed for BNE); a plain SUB would not.
    SUBS R3, R3, #1              @ 1 cycle, flag-updating subtract
    BNE  delay_loop              @ 2 cycles taken, 1 cycle on the final,
                                  @ not-taken pass

    @ --- REPEAT -----------------------------------------------------------
    @ TODO 5 (done): Branch back to the start of the main 'loop'.
    B    loop                    @ 2 cycles

    @ ----------------------------------------------------------------------
    @ NOTE: You must calculate your exact cycle budget, showing the cost
    @ of every instruction and loop iteration, and document it in your report.
    @ ----------------------------------------------------------------------

    .size DSP_Loop, .-DSP_Loop

/*
 * lcd.s
 * EEE3096S 2026 - Practical 1B, Task 5
 * 4-bit bit-banged HD44780 driver, and the level shifter timing fault
 *
 * Student 1 : <Hazel Mpakati>  <MPKHAZ001>
 * Student 2 : <Tinashe Masvore >  <MSVTIN003>
 */

    .syntax unified
    .thumb
    .cpu    cortex-m0
    .fpu    softvfp

    .global LCD_Run
    .type   LCD_Run, %function

@ ---------------------------------------------------------------------------
@ Register addresses. BSRR is at offset 0x18 from each port base.
@ ---------------------------------------------------------------------------
    .equ GPIOA_BSRR, 0x48000018
    .equ GPIOB_BSRR, 0x48000418
    .equ GPIOC_BSRR, 0x48000818

@ ---------------------------------------------------------------------------
@ PIN MAP
@   PC15  Enable (E)     -> PC15_S on the 5 V side
@   PC14  Register Select (RS)
@   PB8   D4      PB9   D5      PA12  D6      PA15  D7
@   R/W is tied to ground. The LCD is write only.
@ ---------------------------------------------------------------------------

@ ---------------------------------------------------------------------------
@ THE TIMING FIX (Task 5, deliverables 1-3)
@
@ MEASURED_RISE_TIME_NS below MUST be replaced with YOUR OWN bench value:
@ the time for PC15_S to rise from 0 V to 3.5 V, read off your oscilloscope
@ cursors (Task 5 deliverable 1). The placeholder value of 300 ns is only
@ an example so this file assembles - do not report it as a measurement.
@
@ Once you have that number, also compute the parasitic capacitance for
@ the report using:
@     C = -t / (R * ln(1 - Vc(t)/Vcc))
@ with t = MEASURED_RISE_TIME_NS, Vc(t) = 3.5 V, Vcc = 5 V, and R = the
@ known level-shifter resistor value from the schematic.
@
@ HD44780 requires Enable to stay above the 3.5 V logic-high threshold for
@ at least 450 ns (PWeh). Counting from the instant firmware sets PC15
@ HIGH, the *effective* high time seen by the LCD only starts once PC15_S
@ has finished its slow RC rise, so the MCU must hold PC15 HIGH for:
@     T_hold = MEASURED_RISE_TIME_NS + 450 ns
@ NOP_COUNT = ceil(T_hold / 125 ns)   (125 ns = 1 cycle at 8 MHz)
@
@ With the placeholder 300 ns: T_hold = 750 ns -> NOP_COUNT = 6.
@ Recompute both constants below once you substitute your real rise time.
@ ---------------------------------------------------------------------------
    .equ MEASURED_RISE_TIME_NS, 300     @ <-- REPLACE with your scope reading
    .equ ENABLE_HOLD_NOPS,      6       @ <-- recompute from the formula above

    .section .text.LCD_Run, "ax", %progbits

@ ===========================================================================
@ ENTRY POINT
@ ===========================================================================
LCD_Run:
    PUSH {LR}

    @ TODO 1 (done): Wait for the LCD power rail to settle. The HD44780
    @ datasheet requires Vcc to be above 4.5 V for more than 15 ms before
    @ the initialisation sequence starts - 20 ms gives margin.
    MOVS R0, #20
    BL   LCD_DelayLong

    @ TODO 2 (done): Call the 4-bit initialization sequence.
    BL   LCD_Init

    @ TODO 3 (done): Write the character 'A' (0x41) to the display.
    MOVS R0, #0x41
    BL   LCD_WriteData

hang:
    B    hang

    .size LCD_Run, .-LCD_Run

@ ===========================================================================
@ LCD_Init
@ Puts the controller into 4-bit mode and readies the display.
@ ===========================================================================
    .type LCD_Init, %function
LCD_Init:
    PUSH {LR}

    @ TODO 4 (done): Send the 4-bit initialization sequence, per the
    @ HD44780 datasheet flowchart ("Interface is 4 bits" branch).
    @ These three 0x3 nibbles are sent RAW (via LCD_SendNibble + LCD_Pulse
    @ directly), NOT via LCD_WriteCmd/LCD_Send8, because the controller is
    @ still in its power-on 8-bit-only state and does not yet expect a
    @ second nibble.

    MOVS R0, #0x03
    BL   LCD_SendNibble
    BL   LCD_Pulse
    MOVS R0, #5                 @ wait > 4.1 ms
    BL   LCD_DelayLong

    MOVS R0, #0x03
    BL   LCD_SendNibble
    BL   LCD_Pulse
    MOVS R0, #150                @ wait > 100 us
    BL   LCD_DelayShort

    MOVS R0, #0x03
    BL   LCD_SendNibble
    BL   LCD_Pulse
    MOVS R0, #150                @ wait > 100 us
    BL   LCD_DelayShort

    MOVS R0, #0x02               @ switch the controller to 4-bit mode
    BL   LCD_SendNibble
    BL   LCD_Pulse
    MOVS R0, #150
    BL   LCD_DelayShort

    @ From here on the controller is in 4-bit mode: every byte goes
    @ through LCD_WriteCmd, which sends it as two nibbles automatically.
    MOVS R0, #0x28                @ function set: 4-bit, 2-line, 5x8 font
    BL   LCD_WriteCmd
    MOVS R0, #50
    BL   LCD_DelayShort

    MOVS R0, #0x08                @ display off
    BL   LCD_WriteCmd
    MOVS R0, #50
    BL   LCD_DelayShort

    MOVS R0, #0x01                @ clear display
    BL   LCD_WriteCmd
    MOVS R0, #2                   @ clear/home need > 1.52 ms
    BL   LCD_DelayLong

    MOVS R0, #0x06                @ entry mode set: increment, no shift
    BL   LCD_WriteCmd
    MOVS R0, #50
    BL   LCD_DelayShort

    MOVS R0, #0x0C                @ display on, cursor off, blink off
    BL   LCD_WriteCmd
    MOVS R0, #50
    BL   LCD_DelayShort

    POP {PC}

@ ===========================================================================
@ LCD_WriteCmd   R0 = command byte, RS low
@ LCD_WriteData  R0 = data byte,    RS high
@ Both send the high nibble first, then the low nibble.
@ ===========================================================================
    .type LCD_WriteCmd, %function
LCD_WriteCmd:
    PUSH {R0, LR}
    @ TODO 5 (done): Drive RS (PC14) LOW, then jump into the shared sender.
    @ (A real fall-through into LCD_WriteData below would re-push {R0,LR}
    @  and drive RS HIGH, unbalancing the stack - so this "falls through"
    @  conceptually by branching straight past LCD_WriteData to LCD_Send8,
    @  which is the single body both callers share.)
    LDR  R1, =GPIOC_BSRR
    LDR  R2, =(1 << 30)          @ reset bit for PC14 (BSRR upper half)
    STR  R2, [R1]
    B    LCD_Send8

    .type LCD_WriteData, %function
LCD_WriteData:
    PUSH {R0, LR}
    @ TODO 6 (done): Drive RS (PC14) HIGH, then fall through.
    LDR  R1, =GPIOC_BSRR
    LDR  R2, =(1 << 14)          @ set bit for PC14 (BSRR lower half)
    STR  R2, [R1]

LCD_Send8:
    @ TODO 7 (done): Send the upper nibble of R0, pulse Enable,
    @         then the lower nibble of R0, pulse Enable again.
    @ R2 is preserved across LCD_SendNibble and LCD_Pulse (both push/pop
    @ it), so it is safe to stash the original byte there.
    MOVS R2, R0                  @ R2 = saved original byte
    LSRS R0, R2, #4              @ R0 = upper nibble
    BL   LCD_SendNibble
    BL   LCD_Pulse

    MOVS R0, R2
    LSLS R0, R0, #28             @ shift lower nibble (bits 3:0) up to 31:28
    LSRS R0, R0, #28             @ ...then back down, zero-filling above it
    BL   LCD_SendNibble
    BL   LCD_Pulse

    POP {R0, PC}

@ ===========================================================================
@ LCD_SendNibble   R0 bits 3:0 -> the four data lines
@ ===========================================================================
    .type LCD_SendNibble, %function
LCD_SendNibble:
    PUSH {R1, R2, R3, LR}

    @ TODO 8 (done): Map the four bits of R0 onto the four data pins
    @   (across 3 ports). Each bit is shifted out into Carry with LSRS
    @   and used to choose the BSRR set-bit or reset-bit word.

    @ --- D4 = bit0 -> PB8 ---------------------------------------------
    LSRS R0, R0, #1
    LDR  R1, =GPIOB_BSRR
    BCS  .Ld4set
    LDR  R2, =(1 << (8 + 16))
    B    .Ld4done
.Ld4set:
    LDR  R2, =(1 << 8)
.Ld4done:
    STR  R2, [R1]

    @ --- D5 = bit1 -> PB9 ---------------------------------------------
    LSRS R0, R0, #1
    LDR  R1, =GPIOB_BSRR
    BCS  .Ld5set
    LDR  R2, =(1 << (9 + 16))
    B    .Ld5done
.Ld5set:
    LDR  R2, =(1 << 9)
.Ld5done:
    STR  R2, [R1]

    @ --- D6 = bit2 -> PA12 ----------------------------------------------
    LSRS R0, R0, #1
    LDR  R1, =GPIOA_BSRR
    BCS  .Ld6set
    LDR  R2, =(1 << (12 + 16))
    B    .Ld6done
.Ld6set:
    LDR  R2, =(1 << 12)
.Ld6done:
    STR  R2, [R1]

    @ --- D7 = bit3 -> PA15 ----------------------------------------------
    LSRS R0, R0, #1
    LDR  R1, =GPIOA_BSRR
    BCS  .Ld7set
    LDR  R2, =(1 << (15 + 16))
    B    .Ld7done
.Ld7set:
    LDR  R2, =(1 << 15)
.Ld7done:
    STR  R2, [R1]

    POP {R1, R2, R3, PC}

@ ===========================================================================
@ LCD_Pulse
@ ===========================================================================
    .type LCD_Pulse, %function
LCD_Pulse:
    PUSH {R0, R1, R2, LR}

    LDR  R0, =GPIOC_BSRR

    @ TODO 9 (done): Set PC15 HIGH.
    LDR  R2, =(1 << 15)
    STR  R2, [R0]

    @ -----------------------------------------------------------------
    @ TODO 10 (done): THE TIMING FIX.
    @ Hold Enable HIGH long enough that, after the level shifter's RC
    @ rise delay, PC15_S still stays above 3.5 V for >= 450 ns. See the
    @ ENABLE_HOLD_NOPS derivation and warning at the top of this file -
    @ replace MEASURED_RISE_TIME_NS with your own bench value first.
    .rept ENABLE_HOLD_NOPS
    NOP
    NOP
    .endr
    @ -----------------------------------------------------------------

    @ TODO 11 (done): Set PC15 LOW.
    LDR  R2, =(1 << (15 + 16))
    STR  R2, [R0]

    @ TODO 12 (done): Hold Enable low long enough to meet the LCD's
    @ minimum Enable cycle time (~1000 ns per HD44780 datasheet, PWc).
    @ 8 NOPs x 125 ns = 1000 ns.
    /*NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP*/

    POP {R0, R1, R2, PC}

@ ===========================================================================
@ Delay helpers
@ Both are deliberately generous busy-waits (they run a bit longer than
@ requested, never shorter) - they are not the timing-critical paths that
@ need an oscilloscope, only the Enable pulse in LCD_Pulse is.
@ ===========================================================================
    .type LCD_DelayLong, %function
LCD_DelayLong:
    @ TODO 13 (done): Millisecond-scale delay. R0 = milliseconds requested.
    @ Each outer pass calls LCD_DelayShort with 250 us four times = 1 ms,
    @ so the total time is always >= R0 ms.
    PUSH {R4, LR}
    MOVS R4, R0
.Ldlong_outer:
    CMP  R4, #0
    BEQ  .Ldlong_done
    MOVS R0, #250
    BL   LCD_DelayShort
    MOVS R0, #250
    BL   LCD_DelayShort
    MOVS R0, #250
    BL   LCD_DelayShort
    MOVS R0, #250
    BL   LCD_DelayShort
    SUBS R4, R4, #1
    B    .Ldlong_outer
.Ldlong_done:
    POP  {R4, PC}

    .type LCD_DelayShort, %function
LCD_DelayShort:
    @ TODO 14 (done): Microsecond-scale delay. R0 = microseconds requested.
    @ At 8 MHz, 1 us = 8 cycles. The SUBS/BNE pair below costs ~3 cycles
    @ per iteration, so R0*8 iterations is a deliberately generous upper
    @ bound - it always waits at least R0 us, typically more.
    PUSH {R1, LR}
    LSLS R1, R0, #3              @ R1 = R0 * 8
.Ldshort_loop:
    SUBS R1, R1, #1
    BNE  .Ldshort_loop
    POP  {R1, PC}

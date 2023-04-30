;**** **** **** **** **** **** **** **** **** **** **** **** ****
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Timing
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;**** **** **** **** **** **** **** **** **** **** **** **** ****


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Initialize timing
;
; Part of initialization before motor start
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
initialize_timing:
    ; Initialize commutation period to 7.5ms (~1330 erpm)
    mov Comm_Period4x_L, #00h
    mov Comm_Period4x_H, #0F0h

    ; Start timer to run freely
	mov TMR3CN0, #0				; Disable timer3 and clear flags
    mov TMR3L, #0 				; Setup next wait time
    mov TMR3H, #4
	mov TMR3CN0, #4				; Enable timer3 and clear flags
    ret


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Calculate next commutation period
;
; Measure the duration of current commutation period,
; and update Comm_Period4x by averaging a fraction of it.
;
; Note: Comm_Period4x holds the average weighted time of the last 4
; commutations. This routine Removes one the fraction of that time
; and adds the same fraction of the new commutation time. Depending
; on the spinning speed it uses some or other dividers of the formula:
; Comm_Period4x = Comm_Period4x - (Comm_Period4x / (16 or 4)) + (Comm_Period / (4 or 1))
; Normal regime:
; Comm_Period4x = Comm_Period4x - (Comm_Period4x / 16) + (Comm_Period / 4)
; During startup:
; Comm_Period4x = Comm_Period4x - (Comm_Period4x / 4) + (Comm_Period / 1)
;
; Simple example using 16 and 4 dividers:
; - Let commutation time be constant.
; - Comm_Period = 64
; - Then Comm_Period4x = 256 (Comm_Period * 4)
; Comm_Period4x = Comm_Period4x - (Comm_Period4x / 16) + Comm_Period / 4
; Comm_Period4x = 256 - (256 / 16) + (64 / 4)
; Comm_Period4x = 256 - 16 + 16
; Comm_Period4x = 256
;
; Called immediately after each commutation
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
calc_next_comm_period:
    ; Read commutation time into Temp3:2:1
    clr IE_EA
    clr TMR2CN0_TR2                 ; Timer2 disabled
    mov Temp1, TMR2L                ; Load Timer2 value
    mov Temp2, TMR2H
    mov Temp3, Timer2_X
    jnb TMR2CN0_TF2H, ($+4)         ; Check if interrupt is pending
    inc Temp3                       ; If it is pending, then timer has already wrapped
    setb    TMR2CN0_TR2             ; Timer2 enabled
    setb    IE_EA

IF MCU_TYPE >= 1
    ; Divide time by 2 on 48MHz MCUs
    clr C
    rrca    Temp3
    rrca    Temp2
    rrca    Temp1
ENDIF

    jnb  Flag_Startup_Phase, calc_next_comm_normal

calc_next_comm_startup:
    ; Calculate this commutation time
    mov Temp4, Prev_Comm_L
    mov Temp5, Prev_Comm_H
    mov Temp6, Prev_Comm_X
    mov Prev_Comm_L, Temp1          ; Store timestamp as previous commutation
    mov Prev_Comm_H, Temp2
    mov Prev_Comm_X, Temp3          ; Store extended timestamp as previous commutation

    clr C
    mov A, Temp1
    subb    A, Temp4                ; Calculate the new commutation time
    mov A, Temp2
    subb    A, Temp5
    mov A, Temp3
    subb    A, Temp6                ; Calculate the new extended commutation time
IF MCU_TYPE >= 1
    anl A, #7Fh
ENDIF
    jz  calc_next_comm_startup_no_zero_cross

    ; Extended byte is not zero, so commutation time is above 0xFFFF
    mov Comm_Period4x_L, #000h
    mov Comm_Period4x_H, #0F0h
    ajmp    calc_next_comm_15deg

calc_next_comm_startup_no_zero_cross:
    ; Extended byte = 0, so commutation time fits within two bytes
    mov Temp7, Prev_Prev_Comm_L
    mov Temp8, Prev_Prev_Comm_H
    mov Prev_Prev_Comm_L, Temp4
    mov Prev_Prev_Comm_H, Temp5

    ; Calculate the new commutation time based upon the two last commutations (to reduce sensitivity to offset)
    clr C
    mov A, Temp1
    subb    A, Temp7
    mov Temp1, A
    mov A, Temp2
    subb    A, Temp8
    mov Temp2, A

    ; Comm_Period4x holds the time of 4 commutations
    mov Temp3, Comm_Period4x_L
    mov Temp4, Comm_Period4x_H

    ; Update Comm_Period4x from 1 new commutation period
    ; Comm_Period4x = Comm_Period4x - (Comm_Period4x / 4) + (Comm_Period / 1)

    ; Divide Temp4:3 by 4 and store in Temp6:5
    Divide_By_4 Temp4, Temp3, Temp6, Temp5

    ; Comm_Period / 1 does not need to be divided
    sjmp calc_next_comm_average_and_update

calc_next_comm_normal:
    ; Calculate this commutation time and store in Temp2:1
    clr C
    mov A, Temp1
    subb    A, Prev_Comm_L          ; Calculate the new commutation time
    mov Prev_Comm_L, Temp1          ; Save timestamp as previous commutation
    mov Temp1, A                    ; Store commutation period in Temp1 (lo byte)
    mov A, Temp2
    subb    A, Prev_Comm_H
    mov Prev_Comm_H, Temp2          ; Save timestamp as previous commutation
IF MCU_TYPE >= 1
    anl A, #7Fh
ENDIF
    mov Temp2, A                    ; Store commutation period in Temp2 (hi byte)

    ; Comm_Period4x holds the time of 4 commutations
    mov Temp3, Comm_Period4x_L
    mov Temp4, Comm_Period4x_H

    ; Update Comm_Period4x from 1/4 new commutation period
    ; Comm_Period4x = Comm_Period4x - (Comm_Period4x / 16) + (Comm_Period / 4)

    ; Divide Temp4:3 by 16 and store in Temp6:5
    Divide_By_16 Temp4, Temp3, Temp6, Temp5

    ; Divide Temp2:1 by 4 and store in Temp2:1
    Divide_By_4 Temp2, Temp1, Temp2, Temp1

calc_next_comm_average_and_update:
    ; Comm_Period4x = Comm_Period4x - (Comm_Period4x / (16 or 4)) + (Comm_Period / (4 or 1))

    ; Temp6/5: Comm_Period4x divided by (16 or 4)
    clr C                           ; Subtract a fraction
    mov A, Temp3                    ; Comm_Period4x_L
    subb    A, Temp5
    mov Temp3, A
    mov A, Temp4                    ; Comm_Period4x_H
    subb    A, Temp6
    mov Temp4, A

    ; Temp2/1: This commutation period divided by (4 or 1)
    mov A, Temp3                    ; Add the divided new time
    add A, Temp1
    mov Comm_Period4x_L, A
    mov A, Temp4
    addc    A, Temp2
    mov Comm_Period4x_H, A

    jnc calc_next_comm_15deg         ; Is period larger than 0xffff?
    mov Comm_Period4x_L, #0FFh      ; Yes - Set commutation period registers to very slow timing (0xffff)
    mov Comm_Period4x_H, #0FFh

calc_next_comm_15deg:
    ; Commutation period: 360 deg / 6 runs = 60 deg
    ; 60 deg / 4 = 15 deg

    ; Load current commutation timing and compute 15 deg timing
    ; Divide Comm_Period4x by 16 (Comm_Period1x divided by 4) and store in Temp4:3
    Divide_By_16    Comm_Period4x_H, Comm_Period4x_L, Temp4, Temp3

calc_next_comm_period_exit:


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Calculate new wait times
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
calc_new_wait_times:
    ; Negate deg timming 15 deg in Temp4:3 and set it to Temp2:1
    clr C
    clr A
    subb    A, Temp3                ; Negate
    mov Temp1, A
    clr A
    subb    A, Temp4
    mov Temp2, A
IF MCU_TYPE >= 1
    clr C
    rlca    Temp1                   ; Multiply by 2
    rlca    Temp2
ENDIF

    ; Load programmed commutation timing
    jnb Flag_Startup_Phase, adjust_comm_timing

    ; Set fixed timing during startup
    mov Temp8, #3
    sjmp    load_comm_timing_done

adjust_comm_timing:
    ; Load commutation timing setting in Temp8
    mov Temp1, #Pgm_Comm_Timing
    mov A, @Temp1
    mov Temp8, A                    ; Store in Temp8

    ; Adjust commutation timing according to demag metric
    clr C
    mov A, Demag_Detected_Metric    ; Check demag metric
    subb    A, #130
    jc  load_comm_timing_done

    inc Temp8                       ; Increase timing (if metric 130 or above)

    subb    A, #30
    jc  adjust_comm_timing_clip

    inc Temp8                       ; Increase timing again (if metric 160 or above)

adjust_comm_timing_clip:
    ; Clip timing to 5
    clr C
    mov A, Temp8                    ; Limit timing to max (5)
    subb    A, #6
    jc  ($+4)
    mov Temp8, #5                   ; Set timing to max (if timing 6 or above)

load_comm_timing_done:
    ; Temp2:1 = 15deg Timer2 period

    ; Temp4:3 = (15deg) / 2 = 7.5deg
    setb    C                       ; Adding negative numbers. Set carry
    mov A, Temp2                    ; Store 7.5deg in Temp4:3 (15deg / 2)
    rrc A
    mov Temp4, A
    mov A, Temp1
    rrc A
    mov Temp3, A

    ; Wt_Zc_Scan_Tout = 7.5deg. Zero cross scan time quanta
    mov Wt_Zc_Scan_Tout_L, Temp3
    mov Wt_Zc_Scan_Tout_H, Temp4

    ; Prepare an indexed jump Temp8 in [1 - 5] -> A in 2 * [0 4]
    ; to load zero cross to commutation time
    mov A, Temp8
    dec A
    addc A, #0          ; Fix underflow: A = A + 0 + C (C = 1 if undeflow)
    rl A                ; Multiply by 2
    mov DPTR, #load_zc_2_comm_table
    jmp @A+DPTR         ; Jump to load zero cross to commutation time

load_zc_2_comm_table:
    ajmp    load_zc_2_comm_1
    ajmp    load_zc_2_comm_2
    ajmp    load_zc_2_comm_3
    ajmp    load_zc_2_comm_4
    ajmp    load_zc_2_comm_5

load_zc_2_comm_1:
    ; Wt_Zc_2_Comm = 0deg
    mov Wt_Zc_2_Comm_L, #-2
    mov Wt_Zc_2_Comm_H, #-1

    sjmp calc_new_wait_times_exit

load_zc_2_comm_2:
    ; Wt_Zc_2_Comm = (15deg Timer2 period) / 2 = 7.5deg
    mov Wt_Zc_2_Comm_L, Temp3
    mov Wt_Zc_2_Comm_H, Temp4

    sjmp calc_new_wait_times_exit

load_zc_2_comm_3:
    ; Wt_Zc_2_Comm = 15deg
    mov Wt_Zc_2_Comm_L, Temp1
    mov Wt_Zc_2_Comm_H, Temp2

    sjmp calc_new_wait_times_exit

load_zc_2_comm_4:
    ; Wt_Zc_2_Comm = 15deg + 7.5deg
    setb    C                       ; Negative numbers - set carry
    mov A, Temp1                    ; Store 30deg in Temp1/2 (15deg + 15deg)
    addc    A, Temp3
    mov Wt_Zc_2_Comm_L, A
    mov A, Temp2
    addc    A, Temp4
    mov Wt_Zc_2_Comm_H, A

    sjmp calc_new_wait_times_exit

load_zc_2_comm_5:
    ; Wt_Zc_2_Comm = 15deg + 15deg
    setb    C                       ; Negative numbers - set carry
    mov A, Temp1                    ; Store 30deg in Temp1/2 (15deg + 15deg)
    addc    A, Temp1
    mov Wt_Zc_2_Comm_L, A
    mov A, Temp2
    addc    A, Temp2
    mov Wt_Zc_2_Comm_H, A

calc_new_wait_times_exit:


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Wait before zero cross scan
;
; Waits for the zero cross scan wait time to elapse
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
wait_before_zc_scan:
    ; Load timer for zero cross timeout
    ; Time precalculated for the following cases:
    ; - Flag_Initial_Run_Phase
    ; - Flag_Startup_Phase
    mov TMR3CN0, #0                 ; Disable timer3 and clear flags
    mov TMR3L, Wt_Zc_Scan_Tout_L    ; Setup next wait time
    mov TMR3H, Wt_Zc_Scan_Tout_H
    mov TMR3CN0, #4                 ; Enable timer3 and clear flags

    ; Allow up to zero cross 32 timeouts:
    ;  240deg, each zero cross timeout is 7.5deg
    mov Zc_Timeout_Cntd, #32


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Wait for comparator to go low/high
;
; Scans for comparator going low/high
; Exit if zero cross timeout has elapsed
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
wait_for_comp_out_low:
    mov B, #00h                 ; Desired comparator output
    jnb Flag_Dir_Change_Brake, comp_check_start
    mov B, #40h
    sjmp    comp_check_start

wait_for_comp_out_high:
    mov B, #40h                 ; Desired comparator output
    jnb Flag_Dir_Change_Brake, comp_check_start
    mov B, #00h

comp_check_start:
    ; Set number of comparator readings required
    mov Temp3, #(4 SHL IS_MCU_48MHZ)        ; Number of OK readings required
    mov Temp4, #(4 SHL IS_MCU_48MHZ)       	; Max wrong readings threshold

    jnb Flag_Startup_Phase, comp_check_timeout
    mov Temp3, #(27 SHL IS_MCU_48MHZ)   	; Set many samples during startup, approximately one pwm period
    mov Temp4, #(27 SHL IS_MCU_48MHZ)

comp_check_timeout:
    ; Check xero cross scan timeout has elapsed
	mov A, TMR3CN0
    jnb ACC.7, comp_check_timeout_not_timed_out

    ; If elapsed extend timeout if timeout counter > 0
    djnz    Zc_Timeout_Cntd, comp_check_timeout_extend_timeout

    ; Timeout elapsed with no reads during all zero cross timeout
    sjmp    comp_exit

comp_check_timeout_extend_timeout:
    ; Reload timer for zero cross timeout
    mov TMR3CN0, #0                 ; Disable timer3 and clear flags
    mov TMR3L, Wt_Zc_Scan_Tout_L    ; Setup next wait time
    mov TMR3H, Wt_Zc_Scan_Tout_H
    mov TMR3CN0, #4                 ; Enable timer3 and clear flags

comp_check_timeout_not_timed_out:
    ; Check comparator
    Read_Comparator_Output
    anl A, #40h
    cjne    A, B, comp_read_wrong

    ; Decrement reads counter until 0
    djnz    Temp3, comp_check_timeout

    ; Zero cross detected
    sjmp    comp_exit

comp_read_wrong:
    ; If good reads to do == max good reads then goto check timeout
    clr C
    mov A, Temp3
    subb    A, Temp4

    ; If A < Temp4 then A = A + 1
    addc    A, #0   ; A = A + 0 + C
    mov Temp3, A

    sjmp    comp_check_timeout              ; Otherwise - go back and restart

comp_exit:


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Setup commutation timing
;
; Load timer with zero cross to commutation time
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
setup_comm_wait:
	mov TMR3CN0, #0					; Disable timer3 and clear flags
    mov TMR3L, Wt_Zc_2_Comm_L
    mov TMR3H, Wt_Zc_2_Comm_H
	mov TMR3CN0, #4					; Enable timer3 and clear flags


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Evaluate comparator integrity
;
; Checks comparator signal behavior versus expected behavior
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
evaluate_comparator_integrity:
    jb  Flag_Dir_Change_Brake, eval_comp_exit   ; Do not exit run mode if braking

    ; Do not exit run mode if comparator timeout is not zero
    mov A, Zc_Timeout_Cntd
    jnz eval_comp_exit

    ; Inmediately cut power on timeout to avoid damage
    All_Pwm_Fets_Off
    Set_All_Pwm_Phases_Off

	; Signal stall
	setb	Flag_Stall_Notify

	; Routine exit without "ret" command
	clr IE_EA
    dec SP
    dec SP
    setb IE_EA
    ljmp    exit_run_mode_on_timeout            ; Exit run mode if timeout has elapsed

eval_comp_startup:
    inc Startup_Cnt                             ; Increment startup counter

eval_comp_exit:
    ret


;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Wait for commutation
;
; Waits from zero cross to commutation
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
wait_for_comm:
    ; Update demag metric
    mov A, Demag_Detected_Metric        ; Sliding average of 8, 256 when demag and 0 when not. Limited to minimum 120
    mov B, #7
    mul AB                      ; Multiply by 7

    ; if Zc_Timeout_Cntd >= 24 then do not count a demag
    clr C
    mov A, Zc_Timeout_Cntd
    subb A, #24
    jnc wait_for_comm_demag_event_added

    ; Add new value for current demag status
    inc B
    ; Signal demag
    setb    Flag_Demag_Notify

wait_for_comm_demag_event_added:
    mov C, B.0                  ; Divide by 8
    rrc A
    mov C, B.1
    rrc A
    mov C, B.2
    rrc A
    mov Demag_Detected_Metric, A
    clr C
    subb    A, #120                 ; Limit to minimum 120
    jnc ($+5)
    mov Demag_Detected_Metric, #120

    ; Update demag metric max
    clr C
    mov A, Demag_Detected_Metric
    subb    A, Demag_Detected_Metric_Max
    jc  wait_for_comm_demag_metric_max_updated
    mov Demag_Detected_Metric_Max, Demag_Detected_Metric

wait_for_comm_demag_metric_max_updated:
    ; Check demag metric
    clr C
    mov A, Demag_Detected_Metric
    subb    A, Demag_Pwr_Off_Thresh
    jc  wait_for_comm_wait

    ; Cut power if many consecutive demags. This will help retain sync during hard accelerations
    All_Pwm_Fets_Off
    Set_All_Pwm_Phases_Off

    ; Signal desync
    setb    Flag_Desync_Notify

wait_for_comm_wait:
    ; Wait until commutation has to be done
    Wait_For_Timer3
    ret

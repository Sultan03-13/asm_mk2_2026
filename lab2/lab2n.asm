.386

OVERFLOW_H equ 32767
OVERFLOW_L equ 32768

ERROR_SUCCESS           equ 0
ERROR_DIV_ZERO          equ 1
INTEGER_OVERFLOW        equ 2
ERROR_FORMAT_MISMATCH   equ 3
AN_UNACCEPTABLE_SIGN    equ 4

arg1 equ 4
arg2 equ 6
arg3 equ 8
arg4 equ 10

var1 equ -2
var2 equ -4
var3 equ -6
var4 equ -8

stack segment para stack
db 65530 dup(?)
stack ends

data segment para public
    user_input      db 256 dup(?)
    inp_max         db 254
    inp_len         db ?
    mul_flag        db 0
    
    out_dec_buf     db 16 dup (?)
    out_hex_buf     db 9 dup(?)
    
    tmp_num1        db 10 dup(?)
    tmp_len1        db ?
    tmp_num2        db 10 dup(?)
    tmp_len2        db ?
    
    ; ----- сообщения для пользователя -----
    msg_base_prompt db "Select base (d/h): $"
    msg_base_set    db "Base set to $"
    msg_expr_prompt db "Enter expression: $"
    msg_result_dec  db "Result (dec): $"
    msg_result_hex  db "Result (hex): $"
    msg_error       db "Error: $"
    hex_prefix      db " (0x$"
    hex_suffix      db ")$"
    newline         db 13, 10, "$"
    
    err_format_msg  db "invalid format$"
    err_divzero_msg db "division by zero$"
    err_overflow_msg db "overflow$"
    err_op_msg      db "unknown operation$"
    err_base_msg    db "invalid base$"
    
    operand1        dw ?
    operand2        dw ?
    operator_char   db ?
    base_char       db ?            ; сохранённый выбор базы
    
    mul_result_low  dd ?
    normal_result   dw ?
    
    work_buffer     db 10 dup(?)
data ends

code segment para public use16
assume cs:code, ds:data, ss:stack

; ===== вывод символа =====
_disp_char:
    push bp
    mov bp, sp
    mov dl, [bp+arg1]
    mov ah, 2
    int 21h
    mov sp, bp
    pop bp
    ret

; ===== вывод строки с '$'-терминатором =====
_disp_str_dollar:
    push bp
    mov bp, sp
    mov dx, [bp+arg1]
    mov ah, 9
    int 21h
    pop bp
    ret

; ===== вывод строки с 0-терминатором (используется для буферов) =====
_disp_str_zero:
    push bp
    mov bp, sp
    push si
    mov si, [bp+arg1]
_dsz_loop:
    lodsb
    cmp al, 0
    je _dsz_done
    mov dl, al
    mov ah, 2
    int 21h
    jmp _dsz_loop
_dsz_done:
    pop si
    mov sp, bp
    pop bp
    ret

; ===== перевод строки =====
_new_line:
    push bp
    mov bp, sp
    mov dx, offset newline
    mov ah, 9
    int 21h
    mov sp, bp
    pop bp
    ret

; ===== завершение с кодом =====
_terminate:
    push bp
    mov bp, sp
    mov al, 00h
    mov ah, 4ch
    int 21h
    mov sp, bp
    pop bp
    ret

_terminate_ok:
    push bp
    mov bp, sp
    push 0
    call _terminate
    add sp, 2
    mov sp, bp
    pop bp
    ret

; ===== обработчики ошибок с выводом сообщения =====
_err_general:
    push bp
    mov bp, sp
    mov dx, offset msg_error
    mov ah, 9
    int 21h
    pop bp
    ret

_err_divzero:
    push bp
    mov bp, sp
    call _err_general
    mov dx, offset err_divzero_msg
    mov ah, 9
    int 21h
    call _new_line
    mov al, ERROR_DIV_ZERO
    mov ah, 4ch
    int 21h
    mov sp, bp
    pop bp
    ret

_err_overflow:
    push bp
    mov bp, sp
    call _err_general
    mov dx, offset err_overflow_msg
    mov ah, 9
    int 21h
    call _new_line
    mov al, INTEGER_OVERFLOW
    mov ah, 4ch
    int 21h
    mov sp, bp
    pop bp
    ret

_err_format:
    push bp
    mov bp, sp
    call _err_general
    mov dx, offset err_format_msg
    mov ah, 9
    int 21h
    call _new_line
    mov al, ERROR_FORMAT_MISMATCH
    mov ah, 4ch
    int 21h
    mov sp, bp
    pop bp
    ret

_err_operator:
    push bp
    mov bp, sp
    call _err_general
    mov dx, offset err_op_msg
    mov ah, 9
    int 21h
    call _new_line
    mov al, AN_UNACCEPTABLE_SIGN
    mov ah, 4ch
    int 21h
    mov sp, bp
    pop bp
    ret

_err_base:
    push bp
    mov bp, sp
    call _err_general
    mov dx, offset err_base_msg
    mov ah, 9
    int 21h
    call _new_line
    mov al, ERROR_FORMAT_MISMATCH
    mov ah, 4ch
    int 21h
    mov sp, bp
    pop bp
    ret

; ===== преобразование шестнадцатеричной цифры =====
_hex_digit:
    push cx
    mov cl, al
    shr al, 4
    call _nibble_to_ascii
    mov al, cl
    and al, 0Fh
    call _nibble_to_ascii
    pop cx
    ret

_nibble_to_ascii:
    cmp al, 9
    jbe _nibble_digit
    add al, 7
_nibble_digit:
    add al, '0'
    mov [di], al
    inc di
    ret

; ===== преобразование 16-битного знакового в десятичную строку =====
_int16_to_dec:
    push bp
    mov bp, sp
    mov di, [bp+4] 
    mov ax, [bp+6]
    cmp ax, 0
    jns _i16d_pos
    mov byte ptr [di], '-'
    inc di
    neg ax
_i16d_pos:
    cmp ax, 0
    jne _i16d_not_zero
    mov byte ptr [di], '0'
    inc di
    mov byte ptr [di], 0
    jmp _i16d_done
_i16d_not_zero:
    xor cx, cx
    mov bx, 10
_i16d_loop:
    xor dx, dx
    div bx
    push dx
    inc cx
    cmp ax, 0
    jnz _i16d_loop
_i16d_write:
    pop dx
    add dl, '0'
    mov [di], dl
    inc di
    loop _i16d_write
    mov byte ptr [di], 0
_i16d_done:
    mov sp, bp
    pop bp
    ret

; ===== преобразование 16-битного знакового в шестнадцатеричную строку =====
_int16_to_hex:
    push bp
    mov bp, sp
    push di
    push ax
    push bx
    push cx
    mov di, [bp+4]    
    mov ax, [bp+6]    
    mov bl, ah
    mov bh, al
    mov al, bl
    call _hex_digit
    mov al, bh
    call _hex_digit
    mov byte ptr [di], 0
    pop cx
    pop bx
    pop ax
    pop di
    mov sp, bp
    pop bp
    ret

; ===== преобразование 32-битного знакового в десятичную строку =====
_int32_to_dec:
    push bp
    mov bp, sp
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov di, [bp+4] 
    mov ax, [bp+6]
    mov dx, [bp+8]
    cmp dx, 0
    jne _i32d_not_zero
    cmp ax, 0
    jne _i32d_not_zero
    mov byte ptr [di], '0'
    inc di
    mov byte ptr [di], 0
    jmp _i32d_done
_i32d_not_zero:
    cmp dx, 0
    jge _i32d_pos
    not ax
    not dx
    add ax, 1
    adc dx, 0
    mov byte ptr [di], '-'
    inc di
_i32d_pos:
    xor cx, cx
    mov bx, 10
_i32d_convert:
    mov si, ax
    mov ax, dx
    xor dx, dx
    div bx
    xchg ax, si
    div bx
    push dx
    inc cx
    xor dx, dx
    cmp ax, 0
    jne _i32d_convert
_i32d_write:
    pop dx
    add dl, '0'
    mov [di], dl
    inc di
    loop _i32d_write
    mov byte ptr [di], 0
_i32d_done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    mov sp, bp
    pop bp
    ret

; ===== преобразование 32-битного знакового в шестнадцатеричную строку =====
_int32_to_hex:
    push bp
    mov bp, sp
    push di
    push ax
    push dx
    push bx
    push cx
    mov di, [bp+4]     
    mov ax, [bp+6]    
    mov dx, [bp+8]      
    mov bx, ax
    mov cx, dx
    mov ax, cx
    call _write_hex_word
    mov ax, bx
    call _write_hex_word
    mov byte ptr [di], 0  
    pop cx
    pop bx
    pop dx
    pop ax
    pop di
    mov sp, bp
    pop bp
    ret

_write_hex_word:
    push cx
    mov cx, 4
_whw_loop:
    rol ax, 4
    mov dl, al
    and dl, 0Fh
    cmp dl, 9
    jbe _whw_digit
    add dl, 7
_whw_digit:
    add dl, '0'
    mov [di], dl
    inc di
    loop _whw_loop
    pop cx
    ret

; ===== проверка, является ли строка шестнадцатеричной =====
_is_hex_str:
    push bp
    mov bp, sp
    push si
    push bx
    mov si, [bp+4]
    xor bx, bx
    cmp byte ptr [si], '-'
    je _ihs_skip_sign
    cmp byte ptr [si], '+'
    jne _ihs_check_start
_ihs_skip_sign:
    inc si
_ihs_check_start:
    cmp byte ptr [si], '0'
    jne _ihs_not_hex
    mov al, byte ptr [si+1]
    cmp al, 'x'
    je _ihs_hex_found
    cmp al, 'X'
    je _ihs_hex_found
    jmp _ihs_not_hex
_ihs_hex_found:
    add si, 2
    mov bx, si
    mov al, [si]
    cmp al, 0
    je _ihs_error
    cmp al, ' '
    je _ihs_error
_ihs_hex_loop:
    mov al, [si]
    cmp al, 0
    je _ihs_ok
    cmp al, ' '
    je _ihs_ok
    cmp al, '0'
    jb _ihs_error
    cmp al, '9'
    jbe _ihs_next
    and al, 0DFh
    cmp al, 'A'
    jb _ihs_error
    cmp al, 'F'
    ja _ihs_error
_ihs_next:
    inc si
    jmp _ihs_hex_loop
_ihs_not_hex:
    mov ax, 0
    clc
    jmp _ihs_end
_ihs_ok:
    mov ax, 1
    clc
    jmp _ihs_end
_ihs_error:
    mov ax, 0
    stc
_ihs_end:
    pop bx
    pop si
    mov sp, bp
    pop bp
    ret

; ===== преобразование строки в число (десятичное или hex) =====
_str_to_int:
    push bp
    mov bp, sp
    push si
    mov si, word ptr [bp + arg1]
    mov bx, si
    cmp byte ptr [bx], '-'
    je _sti_skip_s
    cmp byte ptr [bx], '+'
    jne _sti_check_hex
_sti_skip_s:
    inc bx
_sti_check_hex:
    cmp byte ptr [bx], '0'
    jne _sti_call_dec
    mov al, byte ptr [bx + 1]
    cmp al, 'x'
    je _sti_call_hex
    cmp al, 'X'
    je _sti_call_hex
_sti_call_dec:
    push si
    call _dec_to_int
    pop cx
    jmp _sti_done
_sti_call_hex:
    xor dx, dx
    cmp byte ptr [si], '-'
    jne _sti_hex_pos
    mov dx, 1
_sti_hex_pos:
    push bx
    call _hex_to_int
    pop cx
    jc _sti_done
    cmp dx, 0
    jz _sti_done
    cmp ax, 8000h
    je _sti_min_int
    neg ax
    jo _sti_overflow
    clc
    jmp _sti_done
_sti_min_int:
    mov ax, 8000h
    clc
    jmp _sti_done
_sti_overflow:
    mov ax, INTEGER_OVERFLOW
    call _err_overflow
    stc
_sti_done:
    pop si
    mov sp, bp
    pop bp
    ret

; ===== преобразование шестнадцатеричной строки в число =====
_hex_to_int:
    push bp
    mov bp, sp
    push si
    push dx
    mov si, word ptr [bp + arg1]
    add si, 2
    xor ax, ax
_hti_loop:
    mov cl, byte ptr [si]
    cmp cl, 0
    jz _hti_done
    cmp ah, 0
    jne _hti_check_ov
    jmp _hti_shift_ok
_hti_check_ov:
    and ah, 0F0h
    cmp ah, 0
    je _hti_shift_ok
    jmp _hti_overflow
_hti_shift_ok:
    shl ax, 4
    cmp cl, '9'
    jbe _hti_digit
    and cl, 0DFh
    sub cl, 'A'-10
    jmp _hti_accum
_hti_digit:
    sub cl, '0'
_hti_accum:
    or al, cl
    inc si
    jmp _hti_loop
_hti_overflow:
    mov ax, INTEGER_OVERFLOW
    stc
    call _err_overflow
    jmp _hti_end
_hti_done:
    clc
_hti_end:
    pop dx
    pop si
    mov sp, bp
    pop bp
    ret

; ===== преобразование десятичной строки в число =====
_dec_to_int:
    push bp
    mov bp, sp
    push si
    push bx
    mov si, word ptr [bp + arg1]
    xor ax, ax
    xor bx, bx
_dti_skip:
    cmp byte ptr [si], ' '
    jne _dti_sign
    inc si
    jmp _dti_skip
_dti_sign:
    cmp byte ptr [si], '-'
    jne _dti_plus
    mov bx, 1
    inc si
    jmp _dti_loop
_dti_plus:
    cmp byte ptr [si], '+'
    jne _dti_loop
    inc si
_dti_loop:
    mov cl, byte ptr [si]
    cmp cl, '0'
    jb _dti_done
    cmp cl, '9'
    ja _dti_done
    sub cl, '0'
    cmp ax, 3276
    jg _dti_overflow
    imul ax, 10
    jo _dti_overflow
    xor ch, ch
    add ax, cx
    jo _dti_overflow
    inc si
    jmp _dti_loop
_dti_done:
    cmp bx, 0
    jz _dti_check_pos
    cmp ax, 8000h
    je _dti_min_int
    neg ax
    jo _dti_overflow
    clc
    jmp _dti_end
_dti_check_pos:
    cmp ax, 0
    jge _dti_pos_ok
    jmp _dti_overflow
_dti_pos_ok:
    clc
    jmp _dti_end
_dti_min_int:
    mov ax, 8000h
    clc
    jmp _dti_end
_dti_overflow:
    mov ax, INTEGER_OVERFLOW
    call _err_overflow
    stc
_dti_end:
    pop bx
    pop si
    mov sp, bp
    pop bp
    ret

; ===== проверка формата первого числа =====
_validate_num1:
    push bp
    mov bp, sp
    push si
    push bx
    mov si, offset tmp_num1  
    xor bx, bx
    push si
    call _is_hex_str
    pop cx
    cmp ax, 1
    je _v1_hex_valid
    mov al, [si]              
    cmp al, '-'
    je _v1_sign
    cmp al, '+'
    je _v1_sign
    jmp _v1_digit_start
_v1_sign:
    inc bx
_v1_digit_start:
    mov al, [si + bx]
    cmp al, 0
    je _v1_error
    cmp al, 13
    je _v1_error
_v1_loop:
    mov al, [si + bx]
    cmp al, 0
    je _v1_ok
    cmp al, 13
    je _v1_ok
    cmp al, ' '
    je _v1_ok
    cmp al, '0'
    jl _v1_error
    cmp al, '9'
    jg _v1_error
    inc bx
    jmp _v1_loop
_v1_ok:
    cmp bx, 0
    je _v1_error
    cmp bx, 1
    jne _v1_ok_exit
    mov al, [si]
    cmp al, '-'
    je _v1_error
    cmp al, '+'
    je _v1_error
_v1_ok_exit:
    mov ax, 1
    pop bx
    pop si
    mov sp, bp
    pop bp
    ret
_v1_hex_valid:
    mov ax, 1
    pop bx
    pop si
    mov sp, bp
    pop bp
    ret
_v1_error:
    call _err_format
    mov sp, bp
    pop bp
    ret

; ===== проверка формата второго числа =====
_validate_num2:
    push bp
    mov bp, sp
    push si
    push bx
    mov si, offset tmp_num2   
    xor bx, bx
    push si
    call _is_hex_str
    pop cx
    cmp ax, 1
    je _v2_hex_valid
    mov al, [si]               
    cmp al, '-'
    je _v2_sign
    cmp al, '+'
    je _v2_sign
    jmp _v2_digit_start
_v2_sign:
    inc bx
_v2_digit_start:
    mov al, [si + bx]
    cmp al, 0
    je _v2_error
    cmp al, 13
    je _v2_error
_v2_loop:
    mov al, [si + bx]
    cmp al, 0
    je _v2_ok
    cmp al, 13
    je _v2_ok
    cmp al, ' '
    je _v2_ok
    cmp al, '0'
    jl _v2_error
    cmp al, '9'
    jg _v2_error
    inc bx
    jmp _v2_loop
_v2_ok:
    cmp bx, 0
    je _v2_error
    cmp bx, 1
    jne _v2_ok_exit
    mov al, [si]
    cmp al, '-'
    je _v2_error
    cmp al, '+'
    je _v2_error
_v2_ok_exit:
    mov ax, 1
    pop bx
    pop si
    mov sp, bp
    pop bp
    ret
_v2_hex_valid:
    mov ax, 1
    pop bx
    pop si
    mov sp, bp
    pop bp
    ret
_v2_error:
    call _err_format
    mov sp, bp
    pop bp
    ret

; ===== выбор базы (d/h) =====
_select_base:
    push bp
    mov bp, sp
    mov dx, offset msg_base_prompt
    mov ah, 9
    int 21h
    mov dx, offset user_input
    mov byte ptr [user_input], 3
    mov ah, 0Ah
    int 21h
    call _new_line
    cmp byte ptr [user_input+1], 1
    jne _sb_error
    mov al, byte ptr [user_input+2]
    cmp al, 'd'
    je _sb_ok
    cmp al, 'h'
    je _sb_ok
_sb_error:
    call _err_base
_sb_ok:
    mov byte ptr [base_char], al
    ; вывод сообщения о выбранной базе
    mov dx, offset msg_base_set
    mov ah, 9
    int 21h
    mov dl, [base_char]
    mov ah, 2
    int 21h
    call _new_line
    pop bp
    ret

; ===== ввод выражения =====
_read_expr:
    push bp
    mov bp, sp
    push si
    push di
    push bx
    mov dx, offset msg_expr_prompt
    mov ah, 9
    int 21h
    mov dx, offset user_input
    mov byte ptr [user_input], 254
    mov ah, 0Ah
    int 21h
    call _new_line
    mov cl, [user_input+1]
    cmp cl, 0
    je _re_error
    xor si, si
    add si, 2
    mov di, offset tmp_num1
_re_parse1:
    mov al, [user_input+si]
    cmp al, ' '
    je _re_num1_done
    cmp al, 13
    je _re_error
    mov [di], al
    inc di
    inc si
    jmp _re_parse1
_re_num1_done:
    mov byte ptr [di], 0 
_re_skip1:
    inc si
    mov al, [user_input+si]
    cmp al, ' '
    je _re_skip1
    mov [operator_char], al
    inc si
_re_skip2:
    mov al, [user_input+si]
    cmp al, ' '
    jne _re_parse2
    inc si
    jmp _re_skip2
_re_parse2:
    mov di, offset tmp_num2
_re_parse2_loop:
    mov al, [user_input+si]
    cmp al, ' '
    je _re_num2_done
    cmp al, 13
    je _re_num2_done
    mov [di], al
    inc di
    inc si
    jmp _re_parse2_loop
_re_num2_done:
    mov byte ptr [di], 0
    cmp byte ptr [user_input+si], 0
    jne _re_error
    mov ax, 1
    jmp _re_exit
_re_error:
    xor ax, ax
_re_exit:
    pop bx
    pop di
    pop si
    mov sp, bp
    pop bp
    ret

; ===== вычисление =====
_compute:
    push bp
    mov bp, sp
    clc
    call _validate_num1
    push offset tmp_num1
    call _str_to_int
    add sp, 2
    jc _comp_error
    mov [operand1], ax
    call _validate_num2
    push offset tmp_num2
    call _str_to_int
    add sp, 2
    jc _comp_error
    mov [operand2], ax
    mov ax, [operand1]
    mov bx, [operand2]
    cmp byte ptr [operator_char], '+'
    je _comp_add
    cmp byte ptr [operator_char], '-'
    je _comp_sub
    cmp byte ptr [operator_char], '*'
    je _comp_mul
    cmp byte ptr [operator_char], '/'
    je _comp_div
    cmp byte ptr [operator_char], '%'
    je _comp_mod
    jmp _comp_op_error
_comp_add:
    add ax, bx
    jo _comp_overflow
    mov [normal_result], ax
    cmp [normal_result], 32767
    jg _comp_overflow
    jmp _comp_done
_comp_sub:
    sub ax, bx
    jo _comp_overflow
    mov [normal_result], ax
    cmp [normal_result], 32767
    jg _comp_overflow
    jmp _comp_done
_comp_mul:
    mov byte ptr [mul_flag], 1
    imul bx
    mov word ptr [mul_result_low], ax
    mov word ptr [mul_result_low+2], dx
    jmp _comp_done
_comp_div:
    cmp bx, 0
    je _comp_divzero
    cwd
    idiv bx
    mov [normal_result], ax
    cmp [normal_result], 32767
    jg _comp_overflow
    jmp _comp_done
_comp_mod:
    cmp bx, 0
    je _comp_divzero
    cwd
    idiv bx
    mov [normal_result], dx
    cmp [normal_result], 32767
    jg _comp_overflow
    jmp _comp_done
_comp_divzero:
    call _err_divzero
_comp_overflow:
    call _err_overflow
_comp_error:
    call _err_format
_comp_op_error:
    call _err_operator
_comp_done:
    mov sp, bp
    pop bp
    ret

; ===== вывод результата =====
_output_result:
    push bp
    mov bp, sp
    cmp [mul_flag], 0
    je _out_normal
_out_mul:
    mov ax, word ptr [mul_result_low]
    mov dx, word ptr [mul_result_low+2]
    push dx
    push ax
    push offset out_dec_buf
    call _int32_to_dec
    add sp, 6
    push dx
    push ax
    push offset out_hex_buf
    call _int32_to_hex
    add sp, 6
    jmp _out_print
_out_normal:
    mov cx, 9
    mov di, offset out_hex_buf
    mov al, 0
    rep stosb
    mov ax, [normal_result]
    push ax
    push offset out_dec_buf
    call _int16_to_dec
    add sp, 4
    mov ax, [normal_result]
    push ax
    push offset out_hex_buf
    call _int16_to_hex
    add sp, 4
_out_print:
    mov dx, offset msg_result_dec
    mov ah, 9
    int 21h
    push offset out_dec_buf
    call _disp_str_zero
    add sp, 2
    call _new_line
    mov dx, offset msg_result_hex
    mov ah, 9
    int 21h
    push offset out_hex_buf
    call _disp_str_zero
    add sp, 2
    call _new_line
    mov sp, bp
    pop bp
    ret

start:
    mov ax, data
    mov ds, ax
    mov ax, stack
    mov ss, ax
    call _select_base
    call _read_expr
    call _compute
    call _output_result
    call _terminate_ok

code ends
end start